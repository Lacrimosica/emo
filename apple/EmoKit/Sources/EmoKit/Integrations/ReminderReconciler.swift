import Foundation
import SwiftData

/// The engine side of task integrations: mirrors reminders into the backlog as tasks.
///
/// New open reminders become tasks with default sizing, flagged for review, tagged with their
/// list's role: only next-action and routine lists are scheduled (see `ListRole`). Upstream edits update
/// only what Reminders owns (title, due date, list, notes), so the user's estimate and energy survive.
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
    /// One checklist item; the checklist block is the sum of its items (ticket 34).
    public static let routineEstimateHours = 5.0 / 60

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

        try relinkNextOccurrences(snapshot, &byExternalID, now: now)

        var seen: Set<String> = []
        for reminder in snapshot.reminders where snapshot.sources.contains(reminder.sourceID) {
            seen.insert(reminder.externalID)
            let link = byExternalID[reminder.externalID]
            let task = try link?.taskID.flatMap { try backlog.task(withID: $0) }

            if let link, let task {
                if reminder.isCompleted, task.isRoutineItem {
                    // A routine item is daily: ticked means done that day, not done for good.
                    try checklists.markDone(task, on: LocalDay(reminder.completedAt ?? now, calendar: calendar), now: now)
                } else if reminder.isCompleted {
                    // Reopened in Emo and not written back yet: Emo's change wins.
                    if !task.isCompleted, task.pendingReminderCompletion != false {
                        try lifecycle.complete(task, now: now, learnTiming: false)
                        result.completed += 1
                    }
                } else if link.contentHash != reminder.contentHash {
                    let stillNeedsReview = task.needsReview   // an upstream edit isn't a user review
                    let stillFromMemory = task.sizedFromMemory
                    var draft = TaskDraft(task)
                    draft.name = Self.title(reminder.title)
                    draft.deadline = reminder.due
                    try lifecycle.update(task, with: draft, now: now)
                    task.needsReview = stillNeedsReview
                    task.sizedFromMemory = stillFromMemory
                    Self.assign(reminder.list, to: task)
                    task.notes = Self.notes(reminder.notes)
                    // Edits Emo hasn't written yet stay applied on top of the new upstream notes.
                    let pending = ReminderNotesWriteBack.decode(task.pendingNotesEditsJSON)
                    if !pending.isEmpty { task.notes = Self.notes(task.parsedNotes.merging(pending)) }
                    result.updated += 1
                }
                // Every sync, not just on edits, so goals in notes imported before goals existed land too.
                if !task.isCompleted { task.applyNotes(seenOn: LocalDay(now, calendar: calendar)) }
                link.contentHash = reminder.contentHash
                link.sourceID = reminder.sourceID
                link.lastSeenAt = now
            } else if !reminder.isCompleted {
                if let link { context.delete(link) }   // its task was deleted in Emo: import afresh
                var draft = Self.draft(for: reminder)
                // Size it like the user sized similar tasks, when there's a confident match (ticket 18).
                var fromMemory = false
                if reminder.list.role != .routine,
                   let suggestion = try SchedulingMemory(context: context).suggest(for: draft.name, area: reminder.list.area,
                                                                                   role: reminder.list.role) {
                    draft.estimatedHours = suggestion.estimatedHours
                    draft.energyCost = suggestion.energyCost
                    draft.category = suggestion.category
                    fromMemory = true
                }
                let task = try backlog.add(draft, now: now)
                task.needsReview = true
                task.sizedFromMemory = fromMemory
                Self.assign(reminder.list, to: task)
                task.notes = Self.notes(reminder.notes)
                task.applyNotes(seenOn: LocalDay(now, calendar: calendar))
                if task.isOngoing || task.isRoutineItem { task.needsReview = false }   // sized from the notes / a checklist item
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
        try checklists.sync(now: now)
        return result
    }

    private var checklists: RoutineChecklist { RoutineChecklist(context: context, calendar: calendar) }

    /// A repeating reminder ticked off can come back as a new reminder for its next date (the ticked
    /// one stays behind, completed). For routine items that's the same checklist item: its link moves
    /// to the new reminder and the tick counts as done that day, instead of a duplicate item.
    private func relinkNextOccurrences(_ snapshot: ReminderSnapshot, _ byExternalID: inout [String: ExternalLink],
                                       now: Date) throws {
        let reminders = snapshot.reminders.filter { snapshot.sources.contains($0.sourceID) }
        let fresh = reminders.filter { !$0.isCompleted && $0.list.role == .routine && byExternalID[$0.externalID] == nil }
        guard !fresh.isEmpty else { return }
        let openIDs = Set(reminders.filter { !$0.isCompleted }.map(\.externalID))
        var ticked = reminders.filter { $0.isCompleted && !openIDs.contains($0.externalID) }
        for reminder in fresh {
            let name = Self.title(reminder.title)
            guard let index = try ticked.firstIndex(where: { old in
                guard old.sourceID == reminder.sourceID, let link = byExternalID[old.externalID],
                      let task = try link.taskID.flatMap({ try backlog.task(withID: $0) }) else { return false }
                return task.isRoutineItem && task.name == name
            }) else { continue }
            let old = ticked.remove(at: index)
            guard let link = byExternalID.removeValue(forKey: old.externalID),
                  let task = try link.taskID.flatMap({ try backlog.task(withID: $0) }) else { continue }
            try checklists.markDone(task, on: LocalDay(old.completedAt ?? now, calendar: calendar), now: now)
            link.externalID = reminder.externalID
            byExternalID[reminder.externalID] = link
        }
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
        try checklists.sync(now: now)
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

    private static func notes(_ raw: String) -> String? {
        raw.allSatisfy(\.isWhitespace) ? nil : raw
    }

    private static func title(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled reminder" : trimmed
    }
}
