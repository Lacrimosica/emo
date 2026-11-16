import Foundation
import SwiftData

/// Ticks (or unticks) a reminder in its provider. Implemented over EventKit by
/// `AppleRemindersWriter`; tests use a fake.
@MainActor
public protocol ReminderCompletionWriting {
    /// Sets the reminder's completion, saving only if it differs. `onlyIfRepeating`: leave a reminder
    /// that doesn't repeat alone. Returns false when the reminder is gone or was left alone.
    func setCompleted(externalID: String, _ completed: Bool, onlyIfRepeating: Bool) async throws -> Bool
}

/// Completion write-back (ticket 35): ticking a task in Emo ticks its reminder.
///
/// `TaskLifecycle` marks the task (`TaskItem.pendingReminderCompletion`); `flush` writes the marks.
/// A failed write stays queued and is retried. Routine checklist items are daily in Emo, so their
/// reminder is ticked only when it repeats in Reminders (which moves it to its next date); a
/// one-off checklist reminder stays open, or it would drop out of the list for good.
@MainActor
public struct ReminderCompletionWriteBack {
    public struct Result: Equatable, Sendable {
        public var written = 0
        public var failed = 0
        /// Marks dropped: no linked reminder, or a one-off routine reminder left open.
        public var dropped = 0
        public var lastError: String?
    }

    private let context: ModelContext
    private let provider: String

    public init(context: ModelContext, provider: String = AppleRemindersSource.provider) {
        self.context = context
        self.provider = provider
    }

    /// Tasks with a completion change still waiting to be written.
    public func pendingTasks() throws -> [TaskItem] {
        try context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.pendingReminderCompletion != nil }))
    }

    @discardableResult
    public func flush(using writer: some ReminderCompletionWriting) async throws -> Result {
        var result = Result()
        for task in try pendingTasks() {
            guard let completed = task.pendingReminderCompletion, let link = try link(for: task) else {
                task.pendingReminderCompletion = nil
                result.dropped += 1
                continue
            }
            do {
                let wrote = try await writer.setCompleted(externalID: link.externalID, completed, onlyIfRepeating: task.isRoutineItem)
                task.pendingReminderCompletion = nil
                if wrote { result.written += 1 } else { result.dropped += 1 }
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
}
