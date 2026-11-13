import EmoKit
import SwiftUI

/// A model dropdown filled from the provider's model list, with a refresh button. Falls back to a
/// text field when the list can't be loaded, so a model can always be entered by hand.
struct ModelPicker: View {
    @Binding var selection: String
    /// Builds a catalog from the current settings (host, key…). Called on each refresh.
    let makeCatalog: () -> any ModelCatalog
    /// Changing this reloads the list (e.g. after the key or host changes).
    let reloadToken: String

    @State private var models: [ModelInfo] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if models.isEmpty {
                    TextField("Model", text: $selection)
                } else {
                    Picker("Model", selection: $selection) {
                        ForEach(options) { Text($0.displayName == $0.id ? $0.id : "\($0.displayName) (\($0.id))").tag($0.id) }
                    }
                }
                if isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Refresh Models", systemImage: "arrow.clockwise", action: reload)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Reload the list of available models")
                }
            }
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.secondary)
            }
        }
        .task(id: reloadToken) { await load() }
    }

    /// The listed models, plus the current selection if it isn't among them.
    private var options: [ModelInfo] {
        models.contains { $0.id == selection } || selection.isEmpty ? models : [ModelInfo(id: selection)] + models
    }

    private func reload() {
        Task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            models = try await makeCatalog().availableModels()
            errorMessage = models.isEmpty ? "No models found. Type a model name instead." : nil
        } catch {
            models = []
            errorMessage = "Couldn't load models: \(error.localizedDescription)"
        }
    }
}
