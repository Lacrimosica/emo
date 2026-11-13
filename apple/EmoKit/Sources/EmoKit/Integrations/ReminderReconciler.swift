import Foundation
import SwiftData

/// The engine side of task integrations: mirrors reminders into the backlog as tasks.
///
/// New open reminders become tasks with default sizing, flagged for review, tagged with their
/// list's role: only next-action and routine lists are scheduled (see `ListRole`). Upstream edits update
/// only what Reminders owns (title, due date, list), so the user's estimate and energy survive.
/// Completion upstream completes the task through `TaskLifecycle` (so its plan is repaired);
/// deletion upstream removes the task if it's still open.
@MainActor
public struct ReminderReconciler {
    public struct Result: Equatable, Sendable {
        public var added = 0
        public var updated = 0
        public var completed = 0
        public var removed = 0
        public var changed: Bool { added + updated + completed + removed > 0 }
    }

    /// Sizing for imported reminders until the user reviews them.
    public static let defaultEstimateHours = 0.5
    public static let routineEstimateHours = 0.25

    private let context: ModelContext
    private let calendar: Calendar

    public init(context: ModelContext, calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
    }

    private var lifecycle: TaskLifecycle { TaskLifecycle(context: context, calendar: calendar) }
    private var backlog: Backlog { Backlog(context: context) }

    @discardableResult
    public func apply(_ snapshot: ReminderSnapshot, now: Date = Date()) throws -> Result {
        var result = Result()
        var byExternalID: [String: ExternalLink] = [:]
        for link in try links(for: snapshot.provider) {
            if byExternalID[link.externalID] == nil { byExternalID[link.externalID] = link } else { context.delete(link) }
        }

        var seen: Set<String> = []
        for reminder in snapshot.reminders where snapshot.sources.contains(reminder.sourceID) {
            seen.insert(reminder.externalID)
            let link = byExternalID[reminder.externalID]
            let task = try link?.taskID.flatMap { try backlog.task(withID: $0) }

            if let link, let task {
                if reminder.isCompleted {
                    if !task.isCompleted {
                        try lifecycle.complete(task, now: now)
                        result.completed += 1
                    }
                } else if link.contentHash != reminder.contentHash {
                    let stillNeedsReview = task.needsReview   // an upstream edit isn't a user review
                    var draft = TaskDraft(task)
                    draft.name = Self.title(reminder.title)
                    draft.deadline = reminder.due
                    try lifecycle.update(task, with: draft, now: now)
                    task.needsReview = stillNeedsReview
                    Self.assign(reminder.list, to: task)
                    result.updated += 1
                }
                link.contentHash = reminder.contentHash
                link.sourceID = reminder.sourceID
                link.lastSeenAt = now
            } else if !reminder.isCompleted {
                if let link { context.delete(link) }   // its task was deleted in Emo: import afresh
                let task = try backlog.add(Self.draft(for: reminder), now: now)
                task.needsReview = true
                Self.assign(reminder.list, to: task)
                let newLink = ExternalLink(provider: snapshot.provider, externalID: reminder.externalID,
                                           sourceID: reminder.sourceID, contentHash: reminder.contentHash, now: now)
                newLink.taskID = task.id
                context.insert(newLink)
                result.added += 1
            }
        }

        for (externalID, link) in byExternalID where !seen.contains(externalID) && snapshot.sources.contains(link.sourceID) {
            if try removeTask(of: link, now: now) { result.removed += 1 }
            context.delete(link)
        }
        try context.save()
        return result
    }

    /// Removes what an integration brought in, except from `keeping` sources: open imported tasks
    /// are deleted (they still live in Reminders); completed ones stay as history.
    @discardableResult
    public func removeAll(provider: String, keeping: Set<String> = [], now: Date = Date()) throws -> Result {
        var result = Result()
        for link in try links(for: provider) where !keeping.contains(link.sourceID) {
            if try removeTask(of: link, now: now) { result.removed += 1 }
            context.delete(link)
        }
        try context.save()
        return result
    }

    private func removeTask(of link: ExternalLink, now: Date) throws -> Bool {
        guard let task = try link.taskID.flatMap({ try backlog.task(withID: $0) }), !task.isCompleted else { return false }
        try lifecycle.delete(task, now: now)
        return true
    }

    private func links(for provider: String) throws -> [ExternalLink] {
        try context.fetch(FetchDescriptor<ExternalLink>(predicate: #Predicate { $0.provider == provider }))
    }

    /// Sizing for a new import. Routine checklist items are quick and light.
    static func draft(for reminder: ExternalReminder) -> TaskDraft {
        let routine = reminder.list.role == .routine
        return TaskDraft(name: title(reminder.title),
                         estimatedHours: routine ? routineEstimateHours : defaultEstimateHours,
                         energyCost: routine ? .low : .medium,
                         deadline: reminder.due)
    }

    private static func assign(_ list: ListAssignment, to task: TaskItem) {
        task.listRole = list.role
        task.listArea = list.area
    }

    private static func title(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled reminder" : trimmed
    }
}
