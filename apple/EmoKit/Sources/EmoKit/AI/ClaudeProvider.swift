import Foundation

/// Claude via the Anthropic Messages API (raw HTTP: there's no official Swift SDK).
///
/// Structured output uses `output_config.format` (JSON Schema), which guarantees a parseable reply;
/// forced tool use isn't available on current models. Server-side refusal fallback is enabled.
public struct ClaudeProvider: LLMProvider {
    public static let defaultModel = "claude-opus-5-5"
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let apiVersion = "2026-10-21"
    static let fallbackBeta = "server-side-fallback-2026-07-01"

    public let id = "claude"
    public let displayName = "Claude"

    private let apiKey: String
    private let model: String
    private let transport: any HTTPTransport

    public init(apiKey: String, model: String = ClaudeProvider.defaultModel, transport: any HTTPTransport = URLSessionTransport()) {
        self.apiKey = apiKey
        self.model = model.isEmpty ? Self.defaultModel : model
        self.transport = transport
    }

    public func availability() async -> LLMAvailability {
        apiKey.trimmingCharacters(in: .whitespaces).isEmpty
            ? .unavailable("Add your Anthropic API key in Settings › AI to use Claude.")
            : .available
    }

    public func generate<Output: StructuredOutput>(
        _ type: Output.Type,
        instructions: String,
        conversation: [ChatTurn]
    ) async throws -> Output {
        if case .unavailable(let why) = await availability() { throw LLMError.unavailable(why) }
        let request = try makeRequest(schema: Output.jsonSchema, instructions: instructions, conversation: conversation)
        let (data, response) = try await HTTPProviderSupport.send(request, via: transport, unreachable: "Couldn't reach Anthropic. Check your connection.")
        guard response.statusCode == 200 else { throw Self.error(status: response.statusCode, body: data) }
        return try HTTPProviderSupport.decode(Output.self, fromJSONText: try Self.replyText(data))
    }

    func makeRequest(schema: String, instructions: String, conversation: [ChatTurn]) throws -> URLRequest {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue(Self.fallbackBeta, forHTTPHeaderField: "anthropic-beta")
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4000,
            "system": instructions,
            "messages": conversation.map { ["role": $0.role.rawValue, "content": $0.text] },
            "output_config": [
                "effort": "low",   // short, simple task
                "format": ["type": "json_schema"],
            ],
            "fallbacks": "default",
        ]
        request.httpBody = try HTTPProviderSupport.jsonBody(body, insertingSchema: schema, at: ["output_config", "format", "schema"])
        return request
    }

    /// The JSON text of the reply: the text block(s), ignoring thinking/fallback blocks.
    static func replyText(_ data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMError.badResponse("not JSON")
        }
        switch json["stop_reason"] as? String {
        case "refusal": throw LLMError.badResponse("Claude declined this request")
        case "max_tokens": throw LLMError.badResponse("the reply was cut off")
        default: break
        }
        let blocks = json["content"] as? [[String: Any]] ?? []
        let text = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
        guard !text.isEmpty else { throw LLMError.badResponse("no text in reply") }
        return text
    }

    static func error(status: Int, body: Data) -> LLMError {
        let message = ((try? JSONSerialization.jsonObject(with: body)) as? [String: Any])
            .flatMap { $0["error"] as? [String: Any] }?["message"] as? String
        switch status {
        case 401: return .unavailable("Anthropic rejected the API key. Check it in Settings › AI.")
        case 402: return .transport("Anthropic reported a billing problem with this account.")
        case 403: return .unavailable("This API key isn't allowed to use that model.")
        case 404: return .unavailable("Claude model not found. Check the model name in Settings › AI.")
        case 429: return .transport("Claude is rate-limited right now. Try again in a moment.")
        case 500, 529: return .transport("Claude is overloaded right now. Try again in a moment.")
        default: return .transport("Claude returned an error (\(status))\(message.map { ": \($0)" } ?? ".")")
        }
    }
}
