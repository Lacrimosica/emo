import Foundation
import SwiftData

/// A unit of work the user wants done. Lives in the backlog until scheduled or completed.
///
/// Named `TaskItem` (not `Task`) to avoid clashing with Swift concurrency's `Task`.
///
/// CloudKit-compatible by construction (see docs/adr/0001-local-first-swiftdata-store.md):
/// every stored property is optional or defaulted, there are no unique constraints,
/// and enums are stored as raw strings behind typed accessors.
@Model
public final class TaskItem {
    public var id: UUID = UUID()
    public var name: String = ""
    public var estimatedHours: Double = 1
    public var energyCostRaw: String = EnergyCost.medium.rawValue
    public var categoryRaw: String = TaskCategory.personal.rawValue
    public var recurrenceRaw: String = Recurrence.none.rawValue
    public var deadline: Date?
    public var requiresTransit: Bool = false
    public var transitMinutes: Int = 0
    public var createdAt: Date = Date()
    public var completedAt: Date?
    /// `LocalDay.key` of a day the user skipped this task for; planning leaves it out of that day.
    public var skippedDayKey: String?
    /// `LocalDay.key` of the first day this task may be planned (set on the next occurrence of a
    /// recurring task, so it doesn't land again on the day the previous one was completed).
    public var availableFromDayKey: String?
    /// Imported with guessed sizing (e.g. from Reminders); cleared when the user edits the task.
    public var needsReview: Bool = false
    /// Role of the integration list this task came from (`ListRole` raw value); nil for tasks
    /// created in Emo. Only schedulable roles are planned.
    public var listRoleRaw: String?
    /// Area of life of that list ("NA - Home" → "Home").
    public var listArea: String?
    /// Notes from the integration item (a reminder's notes), raw. Emo reads the keyed lines
    /// (`ReminderNotes`) and passes the rest to the AI as the user wrote it.
    public var notes: String?
    /// The user's TODAY / THIS WEEK goal from the notes' `when:` line (`ReminderNotes.When` raw value).
    public var whenGoalRaw: String?
    /// `LocalDay.key` of the day that goal was first seen. A goal is about the day (or week) it was
    /// set, so one left over from an earlier day decays to normal priority (see `goal(on:)`).
    public var whenSeenDayKey: String?

    public init(
        name: String,
        estimatedHours: Double,
        energyCost: EnergyCost,
        category: TaskCategory,
        recurrence: Recurrence = .none,
        deadline: Date? = nil,
        requiresTransit: Bool = false,
        transitMinutes: Int = 0,
        createdAt: Date = Date()
    ) {
        self.name = name
        self.estimatedHours = estimatedHours
        self.energyCostRaw = energyCost.rawValue
        self.categoryRaw = category.rawValue
        self.recurrenceRaw = recurrence.rawValue
        self.deadline = deadline
        self.requiresTransit = requiresTransit
        self.transitMinutes = transitMinutes
        self.createdAt = createdAt
    }

    public var energyCost: EnergyCost {
        get { EnergyCost(rawValue: energyCostRaw) ?? .medium }
        set { energyCostRaw = newValue.rawValue }
    }

    public var category: TaskCategory {
        get { TaskCategory(rawValue: categoryRaw) ?? .personal }
        set { categoryRaw = newValue.rawValue }
    }

    public var recurrence: Recurrence {
        get { Recurrence(rawValue: recurrenceRaw) ?? .none }
        set { recurrenceRaw = newValue.rawValue }
    }

    public var listRole: ListRole? {
        get { listRoleRaw.flatMap(ListRole.init(rawValue:)) }
        set { listRoleRaw = newValue?.rawValue }
    }

    /// Whether planning may ever place this task (Someday, Waiting, Inbox… items may not).
    public var isSchedulable: Bool { listRole?.isSchedulable ?? true }

    public var isCompleted: Bool { completedAt != nil }

    /// Records the `when:` goal from the notes. The day it was seen only changes when the goal does,
    /// so re-reading the same notes later doesn't refresh a stale goal.
    public func noteWhenGoal(_ goal: ReminderNotes.When?, seenOn day: LocalDay) {
        guard goal?.rawValue != whenGoalRaw else { return }
        whenGoalRaw = goal?.rawValue
        whenSeenDayKey = goal == nil ? nil : day.key
    }

    /// The goal that's still active on `day`: `today` only on the day it was set, `week` until the
    /// end of that week's Sunday. Otherwise nil (normal priority).
    public func goal(on day: LocalDay, calendar: Calendar = .current) -> PlanningGoal? {
        guard let raw = whenGoalRaw, let goal = ReminderNotes.When(rawValue: raw),
              let seen = whenSeenDayKey.flatMap(LocalDay.init(key:)), day >= seen else { return nil }
        switch goal {
        case .today:
            return day == seen ? .today : nil
        case .week:
            let weekday = calendar.component(.weekday, from: seen.start(in: calendar))   // Sunday = 1
            let sunday = seen.adding(days: (8 - weekday) % 7, calendar: calendar)
            return day <= sunday ? .week(endsAt: sunday.end(in: calendar)) : nil
        }
    }

    /// The keyed lines and free text of `notes`.
    public var parsedNotes: ReminderNotes { ReminderNotes(notes ?? "") }
    /// The parent or section this task sits under (`part of:`), if the notes say.
    public var partOf: String? { parsedNotes.partOf }
    /// What the AI needs to size or understand this task (`context:`), if the notes say.
    public var notesContext: String? { parsedNotes.context }

    /// Whether planning may place this task on `day`.
    public func isPlannable(on day: LocalDay) -> Bool {
        guard !isCompleted, isSchedulable, skippedDayKey != day.key else { return false }
        if let from = availableFromDayKey, day.key < from { return false }
        return true
    }
}
