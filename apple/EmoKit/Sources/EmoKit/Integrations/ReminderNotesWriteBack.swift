import Foundation
import SwiftData

/// Writes keyed lines (`ReminderNotes`) to a reminder's notes. Implemented over EventKit by
/// `AppleRemindersWriter`; tests use a fake.
@MainActor
public protocol ReminderNotesWriting {
    /// Fetches the reminder fresh, merges `changes` onto its current notes (other lines untouched),
    /// saves it if anything changed, and returns the reminder as saved. Returns nil when the
    /// reminder no longer exists.
    func updateNotes(externalID: String, changes: [ReminderNotes.Key: String?]) async throws -> ExternalReminder?
}

/// The engine side of notes write-back (ticket 32): a queue of keyed-line edits per task.
///
/// Queuing applies the edit to the task's notes at once (so Emo and its AI see it) and keeps it
/// pending until the reminder is updated. `flush` writes pending edits through a
/// `ReminderNotesWriting`; a failed write stays queued and is retried on the next sync. Only keyed
/// lines are ever written: the title, due date, list and completion stay owned by Reminders.
@MainActor
public struct ReminderNotesWriteBack {
    public typealias Changes = [ReminderNotes.Key: String?]

    public struct Result: Equatable, Sendable {
        public var written = 0
        public var failed = 0
        /// Edits dropped because their reminder (or task link) is gone.
        public var dropped = 0
        public var lastError: String?
    }

    private let context: ModelContext
    private let calendar: Calendar
    private let provider: String

    public init(context: ModelContext, calendar: Calendar = .current, provider: String = AppleRemindersSource.provider) {
        self.context = context
        self.calendar = calendar
        self.provider = provider
    }

    /// The part of `changes` that would actually change `notes`: a value that differs from the
    /// current one (after trimming), or the removal of a line that's there. Empty values remove.
    public static func minimal(_ changes: Changes, against notes: ReminderNotes) -> Changes {
        var result: Changes = [:]
        for (key, proposed) in changes {
            let value = proposed?.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = (value?.isEmpty ?? true) ? nil : value
            let current = notes.fields[key]
            if let normalized {
                if current != normalized { result[key] = .some(normalized) }
            } else if current != nil {
                result[key] = .some(nil)
            }
        }
        return result
    }

    /// Queues `changes` for the reminder behind `task` and applies them to its notes now.
    /// Returns the edits that were actually needed (empty if the notes already say so).
    @discardableResult
    public func queue(_ changes: Changes, for task: TaskItem, now: Date = Date()) throws -> Changes {
        let needed = Self.minimal(changes, against: task.parsedNotes)
        guard !needed.isEmpty else { return [:] }
        var pending = Self.decode(task.pendingNotesEditsJSON)
        for (key, value) in needed { pending[key] = .some(value) }   // later edits win
        task.pendingNotesEditsJSON = Self.encode(pending)
        let merged = task.parsedNotes.merging(needed)
        task.notes = merged.allSatisfy(\.isWhitespace) ? nil : merged
        task.noteWhenGoal(task.parsedNotes.when, seenOn: LocalDay(now, calendar: calendar))
        try context.save()
        return needed
    }

    /// Tasks with edits still waiting to be written.
    public func pendingTasks() throws -> [TaskItem] {
        try context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.pendingNotesEditsJSON != nil }))
    }

    /// Writes every pending edit. Successful writes update the link's fingerprint so the next sync
    /// doesn't read Emo's own write as an upstream edit.
    @discardableResult
    public func flush(using writer: some ReminderNotesWriting, now: Date = Date()) async throws -> Result {
        var result = Result()
        for task in try pendingTasks() {
            let changes = Self.decode(task.pendingNotesEditsJSON)
            guard !changes.isEmpty, let link = try link(for: task) else {
                task.pendingNotesEditsJSON = nil
                result.dropped += 1
                continue
            }
            do {
                guard let saved = try await writer.updateNotes(externalID: link.externalID, changes: changes) else {
                    task.pendingNotesEditsJSON = nil
                    result.dropped += 1
                    continue
                }
                // The reminder as saved, merged onto its latest notes, becomes what Emo knows.
                task.notes = saved.notes.allSatisfy(\.isWhitespace) ? nil : saved.notes
                task.noteWhenGoal(task.parsedNotes.when, seenOn: LocalDay(now, calendar: calendar))
                task.pendingNotesEditsJSON = nil
                link.contentHash = saved.contentHash
                link.lastSeenAt = now
                result.written += 1
            } catch {
                result.failed += 1
                result.lastError = error.localizedDescription
            }
        }
        try context.save()
        return result
    }

    private func link(for task: TaskItem) throws -> ExternalLink? {
        let provider = provider
        let id: UUID? = task.id
        return try context.fetch(FetchDescriptor<ExternalLink>(
            predicate: #Predicate { $0.provider == provider && $0.taskID == id }
        )).first
    }

    // MARK: Encoding ([key raw value: value or null] as JSON)

    static func encode(_ changes: Changes) -> String? {
        guard !changes.isEmpty else { return nil }
        let dict = Dictionary(uniqueKeysWithValues: changes.map { ($0.key.rawValue, $0.value) })
        guard let data = try? JSONEncoder().encode(dict) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode(_ json: String?) -> Changes {
        guard let data = json?.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: String?].self, from: data) else { return [:] }
        var result: Changes = [:]
        for (raw, value) in dict {
            if let key = ReminderNotes.Key(rawValue: raw) { result[key] = .some(value) }
        }
        return result
    }
}
