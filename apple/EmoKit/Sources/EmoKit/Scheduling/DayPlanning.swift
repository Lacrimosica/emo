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
    }

    private let context: ModelContext
    private let calendar: Calendar
    private let settings: PlannerSettings

    public init(context: ModelContext, calendar: Calendar = .current, settings: PlannerSettings = .default) {
        self.context = context
        self.calendar = calendar
        self.settings = settings
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
        let plannable = tasks.map { t in
            PlannableTask(id: t.id,
                          remaining: max(t.estimatedHours * 3600 - (kept[t.id] ?? 0), 0),
                          energyCost: t.energyCost, deadline: t.deadline, createdAt: t.createdAt)
        }

        let first = try planAndWrite(day, tasks: plannable, replaceable: replaceable, tasksByID: tasksByID, now: now)
        let second = try planAndWrite(next, tasks: first.overflow, replaceable: replaceable, tasksByID: tasksByID, now: now)

        return Summary(planned: result(first, day), spill: result(second, next),
                       unplacedTaskCount: second.overflow.count)
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
            busy: kept.map { DateInterval(start: $0.start, end: $0.end) },
            tasks: tasks,
            energy: try CheckIns(context: context).checkIn(for: day)?.energy,
            alreadyPlanned: alreadyPlanned,
            settings: settings
        ))

        try engine.replacePlannedTaskBlocks(
            on: day, from: from,
            with: plan.blocks.compactMap { b in tasksByID[b.taskID].map { ($0, b.start, b.end) } },
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
