import Foundation

/// A model served by Ollama: locally (`http://localhost:11434`) or Ollama Cloud (`https://ollama.com`,
/// with an API key). Structured output via the `format` JSON Schema field.
public struct OllamaProvider: LLMProvider {
    public static let defaultHost = "http://localhost:11434"
    public static let defaultModel = "gemma3:12b"

    public let id = "ollama"
    public let displayName = "Ollama"

    private let host: String
    private let model: String
    private let apiKey: String?
    private let transport: any HTTPTransport

    public init(host: String = OllamaProvider.defaultHost, model: String = OllamaProvider.defaultModel,
                apiKey: String? = nil, transport: any HTTPTransport = URLSessionTransport()) {
        let trimmed = host.trimmingCharacters(in: .whitespaces)
        self.host = trimmed.isEmpty ? Self.defaultHost : trimmed
        self.model = model.isEmpty ? Self.defaultModel : model
        self.apiKey = apiKey?.isEmpty == true ? nil : apiKey
        self.transport = transport
    }

    var chatURL: URL? {
        URL(string: host.hasSuffix("/") ? host + "api/chat" : host + "/api/chat")
    }

    public func availability() async -> LLMAvailability {
        chatURL == nil ? .unavailable("The Ollama host in Settings › AI isn't a valid URL.") : .available
    }

    public func generate<Output: StructuredOutput>(
        _ type: Output.Type,
        instructions: String,
        conversation: [ChatTurn]
    ) async throws -> Output {
        var (data, response) = try await send(try makeRequest(schema: Output.jsonSchema, instructions: instructions,
                                                              conversation: conversation, disableThinking: true))
        // Models without a thinking mode may reject the `think` field: retry once without it.
        if response.statusCode == 400, Self.errorMessage(data)?.localizedCaseInsensitiveContains("think") == true {
            (data, response) = try await send(try makeRequest(schema: Output.jsonSchema, instructions: instructions,
                                                              conversation: conversation, disableThinking: false))
        }
        guard response.statusCode == 200 else { throw error(status: response.statusCode, body: data) }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = (json["message"] as? [String: Any])?["content"] as? String else {
            throw LLMError.badResponse("unexpected Ollama response")
        }
        return try HTTPProviderSupport.decode(Output.self, fromJSONText: content)
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await HTTPProviderSupport.send(request, via: transport, unreachable: "Couldn't reach Ollama at \(host). Is it running?")
    }

    /// `disableThinking` turns off reasoning on thinking models: for this short structured exchange
    /// it adds minutes of latency (measured: ~85 s vs ~2 s on gemma4:12b) without better answers.
    func makeRequest(schema: String, instructions: String, conversation: [ChatTurn], disableThinking: Bool = true) throws -> URLRequest {
        guard let url = chatURL else { throw LLMError.unavailable("The Ollama host isn't a valid URL.") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        let messages = [["role": "system", "content": instructions]]
            + conversation.map { ["role": $0.role.rawValue, "content": $0.text] }
        var body: [String: Any] = [
            "model": model,
            "messages": messages,
            "stream": false,
            // num_predict caps a runaway reply so a stuck model fails fast instead of hanging.
            "options": ["temperature": 0.1, "num_predict": 1024],
        ]
        if disableThinking { body["think"] = false }
        request.httpBody = try HTTPProviderSupport.jsonBody(body, insertingSchema: schema, at: ["format"])
        return request
    }

    static func errorMessage(_ body: Data) -> String? {
        ((try? JSONSerialization.jsonObject(with: body)) as? [String: Any])?["error"] as? String
    }

    private func error(status: Int, body: Data) -> LLMError {
        let message = Self.errorMessage(body)
        switch status {
        case 401, 403: return .unavailable("Ollama rejected the API key. Check it in Settings › AI.")
        case 404: return .unavailable("Ollama doesn't have the model “\(model)”. Pull it or pick another in Settings › AI.")
        case 429: return .transport("Ollama is rate-limited right now. Try again in a moment.")
        default: return .transport("Ollama returned an error (\(status))\(message.map { ": \($0)" } ?? ".")")
        }
    }
}
