import Foundation
import FoundationModels

/// Apple's on-device model (Foundation Models). Free, private, offline; needs Apple Intelligence.
///
/// Uses guided generation, so replies always match the requested type: `Output` must also be
/// `@Generable` (all of Emo's structured outputs are).
public struct AppleOnDeviceProvider: LLMProvider {
    public let id = "apple"
    public let displayName = "Apple (on-device)"

    public init() {}

    public func availability() async -> LLMAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(.deviceNotEligible):
            return .unavailable("This Mac doesn't support Apple Intelligence. Choose another AI provider in Settings.")
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable("Turn on Apple Intelligence in System Settings to use the on-device assistant.")
        case .unavailable(.modelNotReady):
            return .unavailable("The on-device model is still downloading. Try again in a little while.")
        case .unavailable:
            return .unavailable("The on-device model isn't available right now.")
        }
    }

    public func generate<Output: StructuredOutput>(
        _ type: Output.Type,
        instructions: String,
        conversation: [ChatTurn]
    ) async throws -> Output {
        if case .unavailable(let why) = await availability() { throw LLMError.unavailable(why) }
        guard let generable = type as? any Generable.Type else {
            throw LLMError.badResponse("\(type) isn't supported by the on-device model")
        }
        let session = LanguageModelSession(instructions: instructions)
        let prompt = Self.transcript(conversation) + "\nAssistant:"
        do {
            let result = try await Self.respond(session, prompt: prompt, generating: generable)
            guard let output = result as? Output else { throw LLMError.badResponse("unexpected type") }
            return output
        } catch let error as LanguageModelSession.GenerationError {
            throw LLMError.transport("The on-device model couldn't answer (\(error.localizedDescription)).")
        }
    }

    private static func respond<G: Generable>(_ session: LanguageModelSession, prompt: String, generating: G.Type) async throws -> G {
        try await session.respond(to: prompt, generating: G.self).content
    }
}
