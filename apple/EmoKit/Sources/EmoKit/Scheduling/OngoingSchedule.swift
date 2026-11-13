import Foundation
import SwiftData

/// When an ongoing task's sessions are due (ticket 31).
///
/// The week runs Monday to Sunday. A session counts once it's done (`TaskSession`) or planned
/// (a task block that's staying). Each day gets at most one session; consecutive days are avoided
/// while the rest of the week still has room for the sessions left.
@MainActor
public struct OngoingSchedule {
    private let context: ModelContext
    private let calendar: Calendar

    public init(context: ModelContext, calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
    }

    /// Monday of the week containing `day`.
    public func weekStart(of day: LocalDay) -> LocalDay { Self.weekStart(of: day, calendar: calendar) }

    public static func weekStart(of day: LocalDay, calendar: Calendar = .current) -> LocalDay {
        var monday = calendar
        monday.firstWeekday = 2
        return day.startOfWeek(calendar: monday)
    }

    /// `LocalDay.key`s of the Monday-to-Sunday week containing `day`.
    public static func weekKeys(containing day: LocalDay, calendar: Calendar = .current) -> Set<String> {
        Set(weekStart(of: day, calendar: calendar).days(7, calendar: calendar).map(\.key))
    }

    /// Sessions done in the week containing `day`.
    public func sessionsDone(_ task: TaskItem, inWeekOf day: LocalDay) throws -> [TaskSession] {
        let keys = Set(weekStart(of: day).days(7, calendar: calendar).map(\.key))
        let id: UUID? = task.id
        return try context.fetch(FetchDescriptor<TaskSession>(predicate: #Predicate { $0.taskID == id }))
            .filter { keys.contains($0.dayKey) }
    }

    /// How much session time to plan for `task` on `day`, or nil if no session is due there.
    /// `replaceable` are blocks about to be re-planned (they don't count as planned).
    public func timeDue(_ task: TaskItem, on day: LocalDay, replaceable: Set<UUID> = []) throws -> TimeInterval? {
        guard task.isOngoing, task.isPlannable(on: day) else { return nil }
        let week = weekStart(of: day).days(7, calendar: calendar)
        let done = Set(try sessionsDone(task, inWeekOf: day).map(\.dayKey))
        if done.contains(day.key) { return nil }   // one session a day

        // Days of this week with a staying block of this task, and how much is already on `day`.
        var plannedDays: Set<String> = []
        var keptToday: TimeInterval = 0
        for block in try CalendarEngine(context: context).events(forTask: task.id)
        where block.kind == .taskBlock && !replaceable.contains(block.id) {
            let blockDay = LocalDay(block.start, calendar: calendar)
            guard week.contains(blockDay) else { continue }
            plannedDays.insert(blockDay.key)
            if blockDay == day { keptToday += block.duration }
        }
        let session = task.sessionHours * 3600
        if plannedDays.contains(day.key) {
            return keptToday < session ? session - keptToday : nil
        }

        let accounted = done.union(plannedDays).count
        let left = task.sessionsPerWeek - accounted
        guard left > 0 else { return nil }

        // Spread out: skip the day after a session unless the week is running out of days.
        let daysLeft = week.filter { $0 >= day }.count
        let yesterday = day.adding(days: -1, calendar: calendar).key
        if (done.contains(yesterday) || plannedDays.contains(yesterday)), daysLeft > left { return nil }
        return session
    }

    /// The end of the week containing `day`, when the sessions left must all fit by then.
    public func mustFitBy(_ task: TaskItem, on day: LocalDay) throws -> Date? {
        let week = weekStart(of: day).days(7, calendar: calendar)
        let accounted = Set(try sessionsDone(task, inWeekOf: day).map(\.dayKey)).count
        let daysLeft = week.filter { $0 >= day }.count
        return task.sessionsPerWeek - accounted >= daysLeft ? week[6].end(in: calendar) : nil
    }
}
