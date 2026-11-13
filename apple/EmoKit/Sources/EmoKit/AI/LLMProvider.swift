import Foundation

/// One message in a conversation with a language model.
public struct ChatTurn: Equatable, Sendable, Identifiable {
    public enum Role: String, Sendable { case user, assistant }
    public let id: UUID
    public var role: Role
    public var text: String

    public init(_ role: Role, _ text: String, id: UUID = UUID()) {
        self.id = id
        self.role = role
        self.text = text
    }
}

/// Whether a provider can be used right now, and if not, why (in words for the user).
public enum LLMAvailability: Equatable, Sendable {
    case available
    case unavailable(String)
}

public enum LLMError: Error, Equatable, LocalizedError {
    case unavailable(String)
    case badResponse(String)
    case transport(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let why): why
        case .badResponse(let detail): "The assistant's reply couldn't be understood (\(detail))."
        case .transport(let detail): detail
        }
    }
}

/// A type a provider can produce as structured output.
///
/// `jsonSchema` (a JSON Schema document, as text) describes it for providers that take a schema
/// (Ollama `format`, Claude tool input); on-device Apple models use guided generation instead
/// (see `AppleOnDeviceProvider`).
public protocol StructuredOutput: Decodable, Sendable {
    static var jsonSchema: String { get }
}

/// A language model backend. Vendor SDKs stay behind this protocol so the rest of Emo never
/// depends on one provider.
public protocol LLMProvider: Sendable {
    /// Stable identifier, used in settings ("apple", "ollama", "claude").
    var id: String { get }
    var displayName: String { get }

    func availability() async -> LLMAvailability

    /// Produces one structured reply to `conversation`, following `instructions`.
    func generate<Output: StructuredOutput>(
        _ type: Output.Type,
        instructions: String,
        conversation: [ChatTurn]
    ) async throws -> Output
}

extension LLMProvider {
    /// Renders a conversation as a plain transcript, for providers that take a single prompt.
    public static func transcript(_ conversation: [ChatTurn]) -> String {
        conversation
            .map { "\($0.role == .user ? "User" : "Assistant"): \($0.text)" }
            .joined(separator: "\n")
    }
}
