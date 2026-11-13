import Foundation

public struct ModelInfo: Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var displayName: String

    public init(id: String, displayName: String? = nil) {
        self.id = id
        self.displayName = displayName ?? id
    }
}

/// A provider that can list the models available to the user (for the Settings picker).
public protocol ModelCatalog: Sendable {
    func availableModels() async throws -> [ModelInfo]
}

extension ClaudeProvider: ModelCatalog {
    static let modelsEndpoint = URL(string: "https://api.anthropic.com/v1/models")!

    /// Lists models via the Models API (no tokens used), following pagination.
    public func availableModels() async throws -> [ModelInfo] {
        if case .unavailable(let why) = await availability() { throw LLMError.unavailable(why) }
        var models: [ModelInfo] = []
        var afterID: String?
        repeat {
            var components = URLComponents(url: Self.modelsEndpoint, resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "limit", value: "100")]
                + (afterID.map { [URLQueryItem(name: "after_id", value: $0)] } ?? [])
            var request = URLRequest(url: components.url!)
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
            let (data, response) = try await HTTPProviderSupport.send(request, via: transport, unreachable: "Couldn't reach Anthropic. Check your connection.")
            guard response.statusCode == 200 else { throw Self.error(status: response.statusCode, body: data) }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw LLMError.badResponse("unexpected models response")
            }
            for entry in json["data"] as? [[String: Any]] ?? [] {
                if let id = entry["id"] as? String {
                    models.append(ModelInfo(id: id, displayName: entry["display_name"] as? String))
                }
            }
            afterID = (json["has_more"] as? Bool == true) ? json["last_id"] as? String : nil
        } while afterID != nil
        return models
    }
}

extension OllamaProvider: ModelCatalog {
    /// Lists the models pulled on the Ollama host (`/api/tags`).
    public func availableModels() async throws -> [ModelInfo] {
        guard let chat = chatURL, let url = URL(string: "tags", relativeTo: chat) else {
            throw LLMError.unavailable("The Ollama host isn't a valid URL.")
        }
        var request = URLRequest(url: url.absoluteURL)
        if let apiKey { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await HTTPProviderSupport.send(request, via: transport, unreachable: "Couldn't reach Ollama at \(host). Is it running?")
        guard response.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMError.transport("Ollama couldn't list its models (\(response.statusCode)).")
        }
        return (json["models"] as? [[String: Any]] ?? []).compactMap { ($0["name"] as? String).map { ModelInfo(id: $0) } }
    }
}
