import Foundation
import FoundationModels

/// The assistant's structured reply while turning a loose description into a task.
/// Exactly one of `question` / `task` is set.
@Generable(description: "Either one clarifying question, or the finished task.")
public struct ClarifierReply: StructuredOutput, Equatable {
    @Guide(description: "A single short clarifying question. Leave empty when proposing the task.")
    public var question: String?

    @Guide(description: "The finished task. Leave empty when asking a question.")
    public var task: ProposedTask?

    public init(question: String? = nil, task: ProposedTask? = nil) {
        self.question = question
        self.task = task
    }

    /// Valid for Claude structured outputs (every object closes with `additionalProperties: false`)
    /// and for Ollama's `format`.
    public static let jsonSchema = """
        {
          "type": "object",
          "properties": {
            "question": {
              "anyOf": [{ "type": "string" }, { "type": "null" }],
              "description": "One short clarifying question, or null when proposing the task."
            },
            "task": {
              "anyOf": [
                { "type": "null" },
                {
                  "type": "object",
                  "properties": {
                    "name": { "type": "string", "description": "Short task name, a few words." },
                    "estimatedHours": { "type": "number", "description": "Estimated hours of work." },
                    "energyCost": { "type": "string", "enum": ["low", "medium", "high"] },
                    "category": { "type": "string", "enum": ["external_commitment", "self_care", "personal", "leisure"] }
                  },
                  "required": ["name", "estimatedHours", "energyCost", "category"],
                  "additionalProperties": false
                }
              ]
            }
          },
          "required": ["question", "task"],
          "additionalProperties": false
        }
        """
}

@Generable(description: "A task ready to add to the backlog.")
public struct ProposedTask: Codable, Sendable, Equatable {
    @Guide(description: "Short task name, a few words.")
    public var name: String

    @Guide(description: "Estimated hours of work, e.g. 0.5 or 2.")
    public var estimatedHours: Double

    @Guide(description: "How draining the task is.", .anyOf(["low", "medium", "high"]))
    public var energyCost: String

    @Guide(description: "What kind of task it is.", .anyOf(["external_commitment", "self_care", "personal", "leisure"]))
    public var category: String

    public init(name: String, estimatedHours: Double, energyCost: String, category: String) {
        self.name = name
        self.estimatedHours = estimatedHours
        self.energyCost = energyCost
        self.category = category
    }
}

/// Turns a loose description into a `TaskDraft`, asking at most one question per turn.
///
/// The conversation rules live here, not in any provider: one question at a time, and after
/// `maxQuestions` questions the assistant must propose a task with what it has.
public struct TaskClarifier: Sendable {
    public enum Step: Equatable, Sendable {
        case ask(String)
        case propose(TaskDraft)
    }

    public static let maxQuestions = 4

    public static let instructions = """
        You are a personal scheduling assistant. The user describes something they need to do. \
        Work out a task with: a short name, estimated hours, energy cost (low, medium or high) \
        and a category (external_commitment for meetings and appointments, self_care for exercise, \
        rest and health, personal for errands and admin, leisure for hobbies and socialising).
        Rules:
        - Ask at most ONE short clarifying question per reply, and only if you really need it.
        - Make sensible assumptions instead of asking about minor details.
        - When you can, reply with the task instead of a question.
        """

    private static let mustProposeNow = "You have asked enough questions. Reply with the task now, using your best guesses."

    private let provider: any LLMProvider

    public init(provider: any LLMProvider) {
        self.provider = provider
    }

    /// The next step given the conversation so far (which must end with a user message).
    public func next(_ conversation: [ChatTurn]) async throws -> Step {
        let questionsAsked = conversation.filter { $0.role == .assistant }.count
        let mustPropose = questionsAsked >= Self.maxQuestions
        var instructions = EmoPrompt.base + "\n\n" + Self.instructions
        if mustPropose { instructions += "\n" + Self.mustProposeNow }

        let reply = try await provider.generate(ClarifierReply.self, instructions: instructions, conversation: conversation)

        if let task = reply.task, let draft = Self.draft(from: task) {
            return .propose(draft)
        }
        if !mustPropose, let question = Self.singleQuestion(reply.question) {
            return .ask(question)
        }
        throw LLMError.badResponse(reply.task != nil ? "the proposed task was incomplete" : "no question or task")
    }

    /// Keeps only the first question if the model asked several.
    static func singleQuestion(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if let mark = text.firstIndex(of: "?") {
            return String(text[...mark]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    /// Maps a model proposal onto a valid draft, clamping the estimate and defaulting unknown enums.
    static func draft(from task: ProposedTask) -> TaskDraft? {
        let name = task.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, task.estimatedHours.isFinite else { return nil }
        let hours = min(max((task.estimatedHours * 4).rounded() / 4, 0.25), 24)
        return TaskDraft(
            name: name,
            estimatedHours: hours,
            energyCost: EnergyCost(rawValue: task.energyCost.lowercased()) ?? .medium,
            category: TaskCategory(rawValue: task.category.lowercased()) ?? .personal
        )
    }
}
