import Foundation
import FoundationModels
import SwiftData

/// The assistant's structured reply while adding context to reminders: a question, or edits.
@Generable(description: "Either one clarifying question, or edits to reminders' notes.")
public struct EnrichmentReply: StructuredOutput, Equatable {
    @Guide(description: "One short clarifying question, only if you can't tell which reminders or what context. Otherwise empty.")
    public var question: String?

    @Guide(description: "Edits to make, one per reminder that needs a change. Empty when asking a question.")
    public var edits: [ProposedNotesEdit]

    public init(question: String? = nil, edits: [ProposedNotesEdit] = []) {
        self.question = question
        self.edits = edits
    }

    public static let jsonSchema = """
        {
          "type": "object",
          "properties": {
            "question": {
              "anyOf": [{ "type": "string" }, { "type": "null" }],
              "description": "One short clarifying question, or null when proposing edits."
            },
            "edits": {
              "type": "array",
              "description": "One entry per reminder that needs a change; empty when asking a question.",
              "items": {
                "type": "object",
                "properties": {
                  "reminder": { "type": "string", "description": "The reminder's id from the list, e.g. \\"3\\"." },
                  "partOf": { "anyOf": [{ "type": "string" }, { "type": "null" }], "description": "New 'part of' value, \\"\\" to remove it, null to leave it." },
                  "context": { "anyOf": [{ "type": "string" }, { "type": "null" }], "description": "New 'context' value, \\"\\" to remove it, null to leave it." },
                  "when": { "anyOf": [{ "type": "string", "enum": ["today", "week", ""] }, { "type": "null" }], "description": "\\"today\\", \\"week\\", \\"\\" to remove it, null to leave it." }
                },
                "required": ["reminder", "partOf", "context", "when"],
                "additionalProperties": false
              }
            }
          },
          "required": ["question", "edits"],
          "additionalProperties": false
        }
        """
}

@Generable(description: "Changes to one reminder's keyed note lines.")
public struct ProposedNotesEdit: Codable, Sendable, Equatable {
    @Guide(description: "The reminder's id from the list, e.g. \"3\".")
    public var reminder: String
    @Guide(description: "New 'part of' value, empty string to remove it, or leave out to keep it.")
    public var partOf: String?
    @Guide(description: "New 'context' value (one short line), empty string to remove it, or leave out to keep it.")
    public var context: String?
    @Guide(description: "\"today\", \"week\", empty string to remove it, or leave out to keep it.")
    public var when: String?

    public init(reminder: String, partOf: String? = nil, context: String? = nil, when: String? = nil) {
        self.reminder = reminder
        self.partOf = partOf
        self.context = context
        self.when = when
    }
}

/// Adds context to existing reminders from the chat (ticket 33): the assistant proposes minimal
/// keyed-line edits, Emo validates them, and the user approves each reminder before anything is
/// written (through `ReminderNotesWriteBack`).
///
/// `ongoing` isn't editable here yet (ticket 31).
@MainActor
public struct ReminderEnrichment {
    public enum Step: Equatable {
        case ask(String)
        /// Validated edits, at most one per reminder; empty when nothing needs changing.
        case propose([Proposal])
    }

    /// One reminder's proposed change, ready for review.
    public struct Proposal: Equatable, Identifiable {
        public var taskID: UUID
        public var title: String
        /// The notes before the change.
        public var before: ReminderNotes
        /// Only what actually changes (see `ReminderNotesWriteBack.minimal`).
        public var changes: ReminderNotesWriteBack.Changes
        public var id: UUID { taskID }

        /// The notes after the change.
        public var after: ReminderNotes { ReminderNotes(before.merging(changes)) }
    }

    public static let maxContextLength = 80
    public static let maxPartOfLength = 40
    /// Keeps the prompt small enough for the on-device model.
    public static let defaultCandidateLimit = 30

    public static let rules = """
        The user wants to add context to their existing reminders. Below is a numbered list of \
        them. Propose edits to the keyed lines "part of", "context" and "when" only.
        Rules:
        - Touch as few reminders and keys as possible. Prefer no edit over a guess.
        - Never restate the title in a value, and never rewrite the user's own note text.
        - Values are one short line. "context" at most \(maxContextLength) characters, "part of" at most \(maxPartOfLength).
        - Use null to leave a key as it is, and "" only when the user asks to remove it.
        - If you can't tell which reminders the user means, or what to write, ask ONE short question instead.
        """

    private let provider: any LLMProvider

    public init(provider: any LLMProvider) {
        self.provider = provider
    }

    /// Open tasks that came from Reminders (only those have notes Emo can write back).
    public static func linkedOpenTasks(context: ModelContext, provider: String = AppleRemindersSource.provider) throws -> [TaskItem] {
        let linked = Set(try context.fetch(FetchDescriptor<ExternalLink>(predicate: #Predicate { $0.provider == provider }))
            .compactMap(\.taskID))
        return try Backlog(context: context).openTasks().filter { linked.contains($0.id) }
    }

    /// The tasks most relevant to what the user said, so the prompt stays small: those whose
    /// title, list area or `part of` share words with the conversation. Falls back to the first
    /// `limit` tasks when nothing matches (the user may be describing them indirectly).
    public static func relevant(_ tasks: [TaskItem], to conversation: [ChatTurn], limit: Int = defaultCandidateLimit) -> [TaskItem] {
        guard tasks.count > limit else { return tasks }
        let said = words(conversation.filter { $0.role == .user }.map(\.text).joined(separator: " "))
        let scored = tasks.map { task -> (TaskItem, Int) in
            let haystack = words([task.name, task.listArea ?? "", task.partOf ?? "", task.listRole?.rawValue ?? ""].joined(separator: " "))
            return (task, haystack.intersection(said).count)
        }
        let matching = scored.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }.map(\.0)
        return Array((matching.isEmpty ? tasks : matching).prefix(limit))
    }

    private static func words(_ text: String) -> Set<String> {
        Set(text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count >= 3 })
    }

    /// The instructions: the shared base prompt, the edit rules, and the numbered reminders.
    public static func instructions(for candidates: [TaskItem]) -> String {
        let list = candidates.enumerated().map { "[\($0.offset + 1)] \(EmoPrompt.render($0.element))" }.joined(separator: "\n")
        return EmoPrompt.base + "\n\n" + rules + "\n\nReminders:\n" + list
    }

    /// The next step given the conversation so far (ending with a user message) and the reminders
    /// it may edit.
    public func next(_ conversation: [ChatTurn], candidates: [TaskItem]) async throws -> Step {
        let reply = try await provider.generate(EnrichmentReply.self, instructions: Self.instructions(for: candidates),
                                                conversation: conversation)
        let proposals = Self.proposals(from: reply.edits, candidates: candidates)
        if proposals.isEmpty, let question = TaskClarifier.singleQuestion(reply.question) {
            return .ask(question)
        }
        return .propose(proposals)
    }

    /// Maps the model's edits onto the candidates, validating every value; drops anything invalid,
    /// unknown ids, and edits that wouldn't change a thing. Several edits to one reminder merge.
    static func proposals(from edits: [ProposedNotesEdit], candidates: [TaskItem]) -> [Proposal] {
        var byTask: [UUID: Proposal] = [:]
        var order: [UUID] = []
        for edit in edits {
            let digits = edit.reminder.filter(\.isNumber)
            guard let index = Int(digits), candidates.indices.contains(index - 1) else { continue }
            let task = candidates[index - 1]
            var proposal = byTask[task.id] ?? Proposal(taskID: task.id, title: task.name, before: task.parsedNotes, changes: [:])
            for (key, value) in validated(edit, title: task.name) { proposal.changes[key] = .some(value) }
            proposal.changes = ReminderNotesWriteBack.minimal(proposal.changes, against: proposal.before)
            if byTask[task.id] == nil { order.append(task.id) }
            byTask[task.id] = proposal
        }
        return order.compactMap { byTask[$0] }.filter { !$0.changes.isEmpty }
    }

    /// Cleans one edit: single line, no "#", within length, not just the title; `when` must be
    /// today/week. A key the model left null isn't included; "" means remove.
    static func validated(_ edit: ProposedNotesEdit, title: String) -> ReminderNotesWriteBack.Changes {
        var result: ReminderNotesWriteBack.Changes = [:]
        func clean(_ raw: String, max: Int) -> String? {
            var value = raw.replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "#", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'")))
            if value.isEmpty { return "" }
            if value.lowercased() == title.lowercased() { return nil }   // restating the title adds nothing
            if value.count > max {
                value = String(value.prefix(max))
                if let space = value.lastIndex(of: " "), value.distance(from: value.startIndex, to: space) > max / 2 {
                    value = String(value[..<space])
                }
                value = value.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-"))
            }
            return value
        }
        if let raw = edit.partOf, let value = clean(raw, max: maxPartOfLength) { result[.partOf] = .some(value.isEmpty ? nil : value) }
        if let raw = edit.context, let value = clean(raw, max: maxContextLength) { result[.context] = .some(value.isEmpty ? nil : value) }
        if let raw = edit.when?.trimmingCharacters(in: .whitespaces).lowercased() {
            if raw.isEmpty {
                result[.when] = .some(nil)
            } else if let goal = ReminderNotes("when: \(raw)").when {
                result[.when] = .some(goal.rawValue)
            }
        }
        return result
    }
}
