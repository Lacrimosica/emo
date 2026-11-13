import EmoKit
import SwiftUI

/// The AI provider choice and its non-secret settings. Stored per device (UserDefaults), since e.g.
/// an Ollama host depends on where the app runs; API keys live in that device's Keychain.
enum AISettingsKey {
    static let provider = "ai.provider"
    static let ollamaHost = "ai.ollama.host"
    static let ollamaModel = "ai.ollama.model"
    static let claudeModel = "ai.claude.model"
}

enum AIProviderChoice: String, CaseIterable, Identifiable {
    case apple, ollama, claude
    var id: String { rawValue }

    var label: String {
        switch self {
        case .apple: "Apple (on-device)"
        case .ollama: "Ollama"
        case .claude: "Claude"
        }
    }
}

enum AIProviders {
    /// The provider currently chosen in Settings › AI.
    static func current(defaults: UserDefaults = .standard, keychain: KeychainStore = KeychainStore()) -> any LLMProvider {
        let choice = AIProviderChoice(rawValue: defaults.string(forKey: AISettingsKey.provider) ?? "") ?? .apple
        switch choice {
        case .apple:
            return AppleOnDeviceProvider()
        case .ollama:
            return OllamaProvider(
                host: defaults.string(forKey: AISettingsKey.ollamaHost) ?? OllamaProvider.defaultHost,
                model: defaults.string(forKey: AISettingsKey.ollamaModel) ?? OllamaProvider.defaultModel,
                apiKey: keychain.read(.ollamaAPIKey)
            )
        case .claude:
            return ClaudeProvider(
                apiKey: keychain.read(.claudeAPIKey) ?? "",
                model: defaults.string(forKey: AISettingsKey.claudeModel) ?? ClaudeProvider.defaultModel
            )
        }
    }
}
