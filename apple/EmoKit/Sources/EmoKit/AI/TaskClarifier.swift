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
                    "category": { "type": "string", "description": "Exactly one of the category names listed in the instructions." }
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

    @Guide(description: "Exactly one of the category names listed in the instructions.")
    public var category: String

    public init(name: String, estimatedHours: Double, energyCost: String, category: String) {
        self.name = name
        self.estimatedHours = estimatedHours
        self.energyCost = energyCost
        self.category = category
    }
}

/// A category the assistant may choose, as the user named it.
public struct CategoryOption: Sendable, Equatable {
    public var key: String
    public var name: String

    public init(key: String, name: String) {
        self.key = key
        self.name = name
    }

    /// The four built-ins under their default names (used when no category list is passed).
    public static let builtIns = TaskCategory.builtIns.map { CategoryOption(key: $0.key, name: $0.defaultName) }

    /// What each built-in is for, to help the model choose.
    static let builtInHints: [String: String] = [
        TaskCategory.externalCommitment.key: "meetings and appointments",
        TaskCategory.selfCare.key: "exercise, rest and health",
        TaskCategory.personal.key: "errands and admin",
        TaskCategory.leisure.key: "hobbies and socialising",
    ]
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
        and a category from the list below, written exactly as listed.
        Rules:
        - Ask at most ONE short clarifying question per reply, and only if you really need it.
        - Make sensible assumptions instead of asking about minor details.
        - When you can, reply with the task instead of a question.
        """

    private static let mustProposeNow = "You have asked enough questions. Reply with the task now, using your best guesses."

    private let provider: any LLMProvider
    private let categories: [CategoryOption]

    /// `categories`: the user's categories (built-ins by default); the assistant picks one by name.
    public init(provider: any LLMProvider, categories: [CategoryOption] = CategoryOption.builtIns) {
        self.provider = provider
        self.categories = categories.isEmpty ? CategoryOption.builtIns : categories
    }

    /// The category list for the instructions, with what each built-in is for.
    static func categoryList(_ categories: [CategoryOption]) -> String {
        "Categories:\n" + categories.map { option in
            CategoryOption.builtInHints[option.key].map { "- \(option.name) (\($0))" } ?? "- \(option.name)"
        }.joined(separator: "\n")
    }

    /// The next step given the conversation so far (which must end with a user message).
    /// `memory`: relevant memory notes (`AIMemory.relevant`), added to the instructions.
    public func next(_ conversation: [ChatTurn], memory: [String] = []) async throws -> Step {
        let questionsAsked = conversation.filter { $0.role == .assistant }.count
        let mustPropose = questionsAsked >= Self.maxQuestions
        var instructions = EmoPrompt.base + AIMemory.instructions(memory) + "\n\n" + Self.instructions
            + "\n" + Self.categoryList(categories)
        if mustPropose { instructions += "\n" + Self.mustProposeNow }

        let reply = try await provider.generate(ClarifierReply.self, instructions: instructions, conversation: conversation)

        if let task = reply.task, let draft = Self.draft(from: task, categories: categories) {
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

    /// Maps a model proposal onto a valid draft, clamping the estimate and defaulting unknown values.
    /// The category is matched by name (any case or accents) or key; anything else becomes Personal.
    static func draft(from task: ProposedTask, categories: [CategoryOption] = CategoryOption.builtIns) -> TaskDraft? {
        let name = task.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, task.estimatedHours.isFinite else { return nil }
        let hours = min(max((task.estimatedHours * 4).rounded() / 4, 0.25), 24)
        return TaskDraft(
            name: name,
            estimatedHours: hours,
            energyCost: EnergyCost(rawValue: task.energyCost.lowercased()) ?? .medium,
            category: category(named: task.category, in: categories)
        )
    }

    static func category(named text: String, in categories: [CategoryOption]) -> TaskCategory {
        let wanted = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let match = categories.first {
            $0.key == wanted.lowercased()
                || $0.name.compare(wanted, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        return match.map { TaskCategory(key: $0.key) } ?? .personal
    }
}
