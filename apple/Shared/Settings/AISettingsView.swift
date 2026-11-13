import EmoKit
import SwiftUI

/// Settings › AI: which model powers "Ask Emo", and its credentials.
struct AISettingsView: View {
    @AppStorage(AISettingsKey.provider) private var provider: AIProviderChoice = .apple
    @AppStorage(AISettingsKey.ollamaHost) private var ollamaHost = OllamaProvider.defaultHost
    @AppStorage(AISettingsKey.ollamaModel) private var ollamaModel = OllamaProvider.defaultModel
    @AppStorage(AISettingsKey.claudeModel) private var claudeModel = ClaudeProvider.defaultModel

    @State private var claudeKey = ""
    @State private var ollamaKey = ""
    @State private var keyMessage: String?
    @State private var testResult: TestResult?
    @State private var isTesting = false
    /// Bumped when a key or host is submitted, to reload that provider's model list.
    @State private var claudeToken = UUID()
    @State private var ollamaToken = UUID()

    private let keychain = KeychainStore()

    #if os(macOS)
    private static let device = "Mac"
    private static let ollamaNote = "Use http://localhost:11434 for a local Ollama, or https://ollama.com with an API key."
    #else
    private static let device = "iPhone"
    private static let ollamaNote = """
        Ollama doesn't run on iPhone. To use the one on your Mac, enter the Mac's address on your \
        Wi-Fi, e.g. http://192.168.1.20:11434 (System Settings › Wi-Fi › Details shows it), and start \
        Ollama on the Mac with OLLAMA_HOST=0.0.0.0 so it accepts connections from the network. \
        Or use https://ollama.com with an API key.
        """
    #endif

    enum TestResult: Equatable {
        case ok(String)
        case failed(String)
    }

    var body: some View {
        Form {
            Picker("Provider", selection: $provider) {
                ForEach(AIProviderChoice.allCases) { Text($0.label).tag($0) }
            }

            switch provider {
            case .apple:
                Section {
                    Text("Runs privately on this \(Self.device) with Apple Intelligence. No account or key needed.")
                        .foregroundStyle(.secondary)
                }
            case .ollama:
                Section("Ollama") {
                    TextField("Host", text: $ollamaHost, prompt: Text(OllamaProvider.defaultHost))
                        .onSubmit { ollamaToken = UUID() }
                    SecureField("API key (Ollama Cloud only)", text: $ollamaKey)
                        .onSubmit { saveKey(ollamaKey, .ollamaAPIKey); ollamaToken = UUID() }
                    ModelPicker(selection: $ollamaModel,
                                makeCatalog: { OllamaProvider(host: ollamaHost, model: ollamaModel, apiKey: ollamaKey) },
                                reloadToken: ollamaToken.uuidString)
                    Text(Self.ollamaNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .claude:
                Section("Claude") {
                    SecureField("Anthropic API key", text: $claudeKey)
                        .onSubmit { saveKey(claudeKey, .claudeAPIKey); claudeToken = UUID() }
                    ModelPicker(selection: $claudeModel,
                                makeCatalog: { ClaudeProvider(apiKey: claudeKey, model: claudeModel) },
                                reloadToken: claudeToken.uuidString)
                    Text("Requests are billed to your Anthropic account. Haiku is the cheapest and is plenty for task chat. Keys are stored in your Keychain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let keyMessage {
                Text(keyMessage).font(.callout).foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button("Test Connection", action: test)
                        .disabled(isTesting)
                    if isTesting { ProgressView().controlSize(.small) }
                    Spacer()
                }
                switch testResult {
                case .ok(let detail): Label(detail, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                case .failed(let detail): Label(detail, systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                case nil: EmptyView()
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            claudeKey = keychain.read(.claudeAPIKey) ?? ""
            ollamaKey = keychain.read(.ollamaAPIKey) ?? ""
        }
        .onChange(of: provider) { testResult = nil }
        .onDisappear {
            // Keys are saved on Return, and again when the window closes, so nothing typed is lost.
            saveKey(claudeKey, .claudeAPIKey, quiet: true)
            saveKey(ollamaKey, .ollamaAPIKey, quiet: true)
        }
    }

    private func saveKey(_ value: String, _ account: KeychainStore.Account, quiet: Bool = false) {
        do {
            try keychain.write(value, for: account)
            if !quiet { keyMessage = value.isEmpty ? "Key removed." : "Key saved to your Keychain." }
        } catch {
            keyMessage = error.localizedDescription
        }
    }

    /// Saves keys, then asks the chosen provider to clarify a tiny sample task.
    private func test() {
        saveKey(claudeKey, .claudeAPIKey, quiet: true)
        saveKey(ollamaKey, .ollamaAPIKey, quiet: true)
        isTesting = true
        testResult = nil
        let provider = AIProviders.current()
        Task {
            defer { isTesting = false }
            if case .unavailable(let why) = await provider.availability() {
                testResult = .failed(why)
                return
            }
            do {
                let step = try await TaskClarifier(provider: provider).next([ChatTurn(.user, "Buy milk at the corner shop, 15 minutes")])
                switch step {
                case .propose(let draft): testResult = .ok("Working. Proposed “\(draft.name)”.")
                case .ask(let question): testResult = .ok("Working. It asked: “\(question)”")
                }
            } catch {
                testResult = .failed(error.localizedDescription)
            }
        }
    }
}
