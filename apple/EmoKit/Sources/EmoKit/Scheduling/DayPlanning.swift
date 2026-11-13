import Foundation
import SwiftData

/// Runs `DayPlanner` against stored data and writes the result through `CalendarEngine`.
///
/// Planning a day re-plans it **and the following day** as one pass: both days' replaceable task
/// blocks (unlocked, Emo-owned, not yet started) are released, the day is filled first, and whatever
/// doesn't fit spills into the next day. Fixed events, locked blocks and the past are never touched.
@MainActor
public struct DayPlanning {
    public struct DayResult: Equatable, Sendable {
        public var day: LocalDay
        public var planned: TimeInterval
        public var taskCount: Int
    }

    public struct Summary: Equatable, Sendable {
        public var planned: DayResult
        /// The following day, which receives the overflow.
        public var spill: DayResult
        /// Tasks with work left that fit on neither day.
        public var unplacedTaskCount: Int
        /// Names of tasks marked `when: today` for the planned day that didn't fully fit on it.
        public var unmetTodayGoals: [String] = []
    }

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

    @discardableResult
    public func plan(_ day: LocalDay, now: Date = Date()) throws -> Summary {
        let next = day.adding(days: 1, calendar: calendar)
        let tasks = try Backlog(context: context).openTasks()
        let tasksByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })

        // Release both days' replaceable blocks before measuring what's left to do.
        var replaceable: Set<UUID> = []
        for d in [day, next] {
            replaceable.formUnion(try engine.replaceableTaskBlocks(on: d, from: from(d, now), calendar: calendar).map(\.id))
        }
        let kept = try keptTaskTime(excluding: replaceable)
        let ongoing = OngoingSchedule(context: context, calendar: calendar)
        // Learned time-of-day preferences (ticket 20), worked out once per plan.
        let learned = Dictionary(uniqueKeysWithValues: try TimeOfDayMemory(context: context, calendar: calendar)
            .learned().map { ($0.group, $0.window) })
        func window(_ t: TaskItem) -> PreferredWindow? { learned[TimeOfDayMemory.group(for: t)] }
        func plannable(_ t: TaskItem, on d: LocalDay) throws -> PlannableTask? {
            if t.isOngoing {
                // A session is planned like a normal task of one session's length (ticket 31).
                guard let due = try ongoing.timeDue(t, on: d, replaceable: replaceable) else { return nil }
                return PlannableTask(id: t.id, remaining: due, energyCost: t.energyCost,
                                     deadline: try ongoing.mustFitBy(t, on: d), createdAt: t.createdAt,
                                     transit: t.requiresTransit ? TimeInterval(max(t.transitMinutes, 0) * 60) : 0,
                                     goal: t.goal(on: d, calendar: calendar), preferredWindow: window(t))
            }
            return PlannableTask(id: t.id,
                          remaining: max(t.estimatedHours * 3600 - (kept[t.id] ?? 0), 0),
                          energyCost: t.energyCost, deadline: t.deadline, createdAt: t.createdAt,
                          transit: t.requiresTransit ? TimeInterval(max(t.transitMinutes, 0) * 60) : 0,
                          goal: t.goal(on: d, calendar: calendar), preferredWindow: window(t))
        }

        // Day one gets every task it may hold; day two gets day one's overflow plus tasks that
        // weren't allowed on day one (skipped for it, or not available until day two).
        let firstTasks = try tasks.filter { $0.isPlannable(on: day) }.compactMap { try plannable($0, on: day) }
        let first = try planAndWrite(day, tasks: firstTasks, replaceable: replaceable, tasksByID: tasksByID, now: now)
        // Ongoing tasks are worked out afresh for day two (day one's new blocks now count).
        let laterTasks = try tasks.filter { t in
            t.isOngoing ? t.isPlannable(on: next) : !t.isPlannable(on: day) && t.isPlannable(on: next)
        }.compactMap { try plannable($0, on: next) }
        let secondTasks = first.overflow.filter { o in
            guard let t = tasksByID[o.id] else { return false }
            return !t.isOngoing && t.isPlannable(on: next)
        } + laterTasks
        let second = try planAndWrite(next, tasks: secondTasks, replaceable: replaceable, tasksByID: tasksByID, now: now)

        // A today goal that didn't fit is reported, not silently moved to tomorrow.
        let unmet = first.overflow.filter { $0.goal == .today }.compactMap { tasksByID[$0.id]?.name }
        return Summary(planned: result(first, day), spill: result(second, next),
                       unplacedTaskCount: second.overflow.count, unmetTodayGoals: unmet)
    }

    private func from(_ day: LocalDay, _ now: Date) -> Date {
        max(now, day.start(in: calendar))
    }

    private func result(_ plan: DayPlan, _ day: LocalDay) -> DayResult {
        DayResult(day: day, planned: plan.plannedDuration, taskCount: Set(plan.blocks.map(\.taskID)).count)
    }

    private func planAndWrite(
        _ day: LocalDay,
        tasks: [PlannableTask],
        replaceable: Set<UUID>,
        tasksByID: [UUID: TaskItem],
        now: Date
    ) throws -> DayPlan {
        let dayStart = day.start(in: calendar)
        let dayEnd = day.end(in: calendar)
        let from = from(day, now)
        guard from < dayEnd else { return DayPlan(blocks: [], overflow: tasks) }

        let kept = try engine.events(on: day, calendar: calendar).filter { !replaceable.contains($0.id) }
        let alreadyPlanned = kept.filter { $0.kind == .taskBlock }.reduce(0) { total, e in
            total + DateInterval(start: max(e.start, dayStart), end: min(e.end, dayEnd)).duration
        }

        let plan = DayPlanner.plan(.init(
            day: day, calendar: calendar, notBefore: from,
            busy: kept.filter { !$0.isAllDay }.map { DateInterval(start: $0.start, end: $0.end) },
            tasks: tasks,
            energy: try CheckIns(context: context).checkIn(for: day)?.energy,
            alreadyPlanned: alreadyPlanned,
            settings: settings
        ))

        try engine.replacePlannedTaskBlocks(
            on: day, from: from,
            with: plan.blocks.compactMap { b in
                tasksByID[b.taskID].map { ($0, b.start, b.end, b.kind == .transit ? .transit : .taskBlock) }
            },
            calendar: calendar, now: now
        )
        return plan
    }

    /// Task-block time per task across the whole calendar, ignoring blocks about to be replaced.
    /// Counting kept blocks on every day means re-planning never double-books work.
    private func keptTaskTime(excluding replaceable: Set<UUID>) throws -> [UUID: TimeInterval] {
        let taskBlock = CalendarEventKind.taskBlock.rawValue
        let blocks = try context.fetch(FetchDescriptor<CalendarEvent>(predicate: #Predicate { $0.kindRaw == taskBlock }))
        var result: [UUID: TimeInterval] = [:]
        for block in blocks where !replaceable.contains(block.id) {
            guard let id = block.taskID else { continue }
            result[id, default: 0] += block.duration
        }
        return result
    }
}
