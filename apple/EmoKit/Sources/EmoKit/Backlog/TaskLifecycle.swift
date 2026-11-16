import Foundation
import SwiftData

/// Changes to a task that reshape the calendar: complete, skip, edit, delete, pin.
///
/// Each operation updates the task, adjusts its calendar events through `CalendarEngine`, then
/// re-plans only the days where the task had (or now has) future blocks. Days the task never
/// touched are left exactly as they are.
@MainActor
public struct TaskLifecycle {
    private let context: ModelContext
    private let calendar: Calendar
    private let settings: PlannerSettings

    /// `settings` defaults to the user's saved planner settings.
    public init(context: ModelContext, calendar: Calendar = .current, settings: PlannerSettings? = nil) {
        self.context = context
        self.calendar = calendar
        self.settings = settings ?? PlannerSettingsStore(context: context).load()
    }

    private var engine: CalendarEngine { CalendarEngine(context: context) }

    // MARK: Complete

    /// Marks `task` done. Its future blocks go (one in progress ends now) and the freed time is
    /// re-planned. A recurring task gets its next occurrence, available from the next period.
    /// Returns the next occurrence, if one was created.
    @discardableResult
    /// `learnTiming`: whether `now` is when the user actually did it (false for completions that
    /// arrive from a sync, whose time is only when Emo noticed).
    public func complete(_ task: TaskItem, now: Date = Date(), learnTiming: Bool = true) throws -> TaskItem? {
        guard !task.isCompleted else { return nil }
        if task.isRoutineItem {   // daily: done for today, not for good (ticket 34)
            try RoutineChecklist(context: context, calendar: calendar).markDone(task, on: LocalDay(now, calendar: calendar), now: now)
            return nil
        }
        task.completedAt = now
        if learnTiming {
            try TimeOfDayMemory(context: context, calendar: calendar).record(.completed, for: task, at: now)
            // Estimate vs. the block time that ran before it was ticked (ticket 19).
            let ran = try engine.events(forTask: task.id)
                .filter { $0.kind == .taskBlock && $0.start < now }
                .reduce(0) { $0 + min($1.end, now).timeIntervalSince($1.start) }
            try DurationMemory(context: context).record(task, actualHours: ran / 3600, now: now)
        }
        try context.save()
        let changed = try engine.clearFutureEvents(forTask: task.id, now: now, calendar: calendar)

        let next = try createNextOccurrence(of: task, completedOn: LocalDay(now, calendar: calendar), now: now)
        try replan(changed, now: now)
        return next
    }

    /// Undoes a completion (e.g. ticked by mistake). Doesn't remove a next occurrence already created.
    public func reopen(_ task: TaskItem) throws {
        task.completedAt = nil
        try context.save()
    }

    private func createNextOccurrence(of task: TaskItem, completedOn day: LocalDay, now: Date) throws -> TaskItem? {
        let step: Int
        switch task.recurrence {
        case .none: return nil
        case .daily: step = 1
        case .weekly: step = 7
        }
        let next = TaskItem(
            name: task.name,
            estimatedHours: task.estimatedHours,
            energyCost: task.energyCost,
            category: task.category,
            recurrence: task.recurrence,
            deadline: task.deadline.flatMap { calendar.date(byAdding: .day, value: step, to: $0) },
            requiresTransit: task.requiresTransit,
            transitMinutes: task.transitMinutes,
            createdAt: now
        )
        next.availableFromDayKey = day.adding(days: step, calendar: calendar).key
        context.insert(next)
        try context.save()
        return next
    }

    // MARK: Sessions (ongoing tasks)

    /// Logs a done session of an ongoing task for `day` (its block time there, or one session's
    /// length). The rest of that day's blocks for it go and the week is re-planned around it;
    /// the task stays open.
    @discardableResult
    public func logSession(_ task: TaskItem, on day: LocalDay? = nil, now: Date = Date()) throws -> TaskSession {
        let day = day ?? LocalDay(now, calendar: calendar)
        let blocksToday = try engine.events(forTask: task.id)
            .filter { $0.kind == .taskBlock && LocalDay($0.start, calendar: calendar) == day && $0.start < now }
        let doneHours = blocksToday.reduce(0) { $0 + min($1.end, now).timeIntervalSince($1.start) } / 3600
        let session = TaskSession(taskID: task.id, day: day, hours: doneHours > 0 ? doneHours : task.sessionHours, completedAt: now)
        context.insert(session)
        try context.save()
        try TimeOfDayMemory(context: context, calendar: calendar).record(.completed, for: task, at: now)
        var changed = try engine.clearFutureEvents(forTask: task.id, now: now, onlyOn: day, calendar: calendar)
        changed.insert(day)
        try replan(changed, now: now)
        return session
    }

    // MARK: Skip

    /// Leaves `task` out of `day`: its remaining blocks there go (pinned ones too) and the day is
    /// re-planned without it. It stays in the backlog and can land on the next day.
    public func skip(_ task: TaskItem, on day: LocalDay, now: Date = Date()) throws {
        // Each skipped block counts against its time of day (ticket 20).
        let memory = TimeOfDayMemory(context: context, calendar: calendar)
        for block in try engine.events(forTask: task.id)
        where block.kind == .taskBlock && block.start >= now && LocalDay(block.start, calendar: calendar) == day {
            try memory.record(.skipped, for: task, at: block.start)
        }
        task.skippedDayKey = day.key
        try context.save()
        var changed = try engine.clearFutureEvents(forTask: task.id, now: now, onlyOn: day, calendar: calendar)
        changed.insert(day)
        try replan(changed, now: now)
    }

    // MARK: Edit

    /// Applies `draft` to `task`, renames its blocks, and re-plans days where it has future blocks.
    public func update(_ task: TaskItem, with draft: TaskDraft, now: Date = Date()) throws {
        try draft.validate()
        let transitMinutes = draft.requiresTransit ? draft.transitMinutes : 0
        let schedulingChanged = draft.estimatedHours != task.estimatedHours
            || draft.isOngoing != task.isOngoing
            || (draft.isOngoing && (draft.sessionsPerWeek != task.sessionsPerWeek || draft.sessionHours != task.sessionHours))
            || draft.energyCost != task.energyCost
            || draft.deadline != task.deadline
            || draft.requiresTransit != task.requiresTransit
            || transitMinutes != task.transitMinutes

        task.name = draft.trimmedName
        task.estimatedHours = draft.estimatedHours
        task.energyCost = draft.energyCost
        task.category = draft.category
        task.deadline = draft.deadline
        task.recurrence = draft.recurrence
        task.requiresTransit = draft.requiresTransit
        task.transitMinutes = transitMinutes
        draft.applyOngoing(to: task)
        task.needsReview = false
        task.sizedFromMemory = false
        try context.save()
        try engine.renameEvents(forTask: task)

        if schedulingChanged {
            let days = Set(try engine.events(forTask: task.id)
                .filter { $0.end > now }
                .map { LocalDay(max($0.start, now), calendar: calendar) })
            try replan(days, now: now)
        }
    }

    // MARK: Delete

    /// Deletes `task` and all its events, then re-plans the days it was going to occupy.
    public func delete(_ task: TaskItem, now: Date = Date()) throws {
        let changed = try engine.deleteAllEvents(forTask: task.id, now: now, calendar: calendar)
        context.delete(task)
        try context.save()
        try replan(changed, now: now)
    }

    // MARK: Pin

    /// Puts `task` at a time the user chose. The block is pinned (survives re-planning); the task's
    /// other unpinned future blocks are released so its time isn't double-booked, and every
    /// affected day is re-planned around the pin.
    @discardableResult
    public func pin(_ task: TaskItem, start: Date, end: Date, now: Date = Date()) throws -> CalendarEvent {
        var changed = try engine.clearFutureEvents(forTask: task.id, now: now, includingPinned: false, calendar: calendar)
        let block = try engine.pinTaskBlock(task, start: start, end: end, now: now)
        changed.insert(LocalDay(start, calendar: calendar))
        if task.skippedDayKey == LocalDay(start, calendar: calendar).key {
            task.skippedDayKey = nil   // pinning onto a skipped day un-skips it
            try context.save()
        }
        try replan(changed, now: now)
        return block
    }

    // MARK: Re-planning

    /// Re-plans each changed day that hasn't fully passed. `DayPlanning.plan(d)` also covers d+1,
    /// so a day already covered as the previous day's "next" isn't planned twice.
    private func replan(_ days: Set<LocalDay>, now: Date) throws {
        let today = LocalDay(now, calendar: calendar)
        let planning = DayPlanning(context: context, calendar: calendar, settings: settings)
        var coveredThrough: LocalDay?
        for day in days.filter({ $0 >= today }).sorted() {
            if let covered = coveredThrough, day <= covered { continue }
            try planning.plan(day, now: now)
            coveredThrough = day.adding(days: 1, calendar: calendar)
        }
    }
}
