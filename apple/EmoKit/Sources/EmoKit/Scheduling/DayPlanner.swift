import Foundation

/// Tunables for planning. Ticket 08 makes these user-editable; defaults match the legacy engine.
public struct PlannerSettings: Equatable, Sendable {
    /// Earliest time tasks may be placed, in minutes after local midnight.
    public var dayStartMinutes: Int
    /// Latest time tasks may run until, in minutes after local midnight.
    public var dayEndMinutes: Int
    /// Shortest block a task is split into (a task's final remainder may be shorter).
    public var minimumChunkMinutes: Int
    /// Hours of task work allowed per day, indexed by check-in energy 1…5.
    public var energyBudgetHours: [Int: Double]
    /// Energy assumed for a day without a check-in (e.g. tomorrow, when overflow lands there).
    public var defaultEnergy: Int

    public init(
        dayStartMinutes: Int = 9 * 60,
        dayEndMinutes: Int = 22 * 60,
        minimumChunkMinutes: Int = 30,
        energyBudgetHours: [Int: Double] = [1: 2, 2: 3.5, 3: 5, 4: 6.5, 5: 8],
        defaultEnergy: Int = 3
    ) {
        self.dayStartMinutes = dayStartMinutes
        self.dayEndMinutes = dayEndMinutes
        self.minimumChunkMinutes = minimumChunkMinutes
        self.energyBudgetHours = energyBudgetHours
        self.defaultEnergy = defaultEnergy
    }

    public static let `default` = PlannerSettings()

    func budget(forEnergy energy: Int?) -> TimeInterval {
        let level = min(max(energy ?? defaultEnergy, 1), 5)
        return (energyBudgetHours[level] ?? 0) * 3600
    }
}

/// A task as the planner sees it: just what affects placement.
public struct PlannableTask: Equatable, Sendable {
    public var id: UUID
    public var remaining: TimeInterval
    public var energyCost: EnergyCost
    public var deadline: Date?
    public var createdAt: Date

    public init(id: UUID, remaining: TimeInterval, energyCost: EnergyCost, deadline: Date?, createdAt: Date) {
        self.id = id
        self.remaining = remaining
        self.energyCost = energyCost
        self.deadline = deadline
        self.createdAt = createdAt
    }
}

public struct PlannedBlock: Equatable, Sendable {
    public var taskID: UUID
    public var start: Date
    public var end: Date
}

public struct DayPlan: Equatable, Sendable {
    public var blocks: [PlannedBlock]
    /// Tasks that did not fit, with the time still left to place.
    public var overflow: [PlannableTask]

    public var plannedDuration: TimeInterval {
        blocks.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
    }
}

/// Places tasks into a day's free time. Pure: no persistence, no UI, no clock.
public enum DayPlanner {
    public struct Input: Sendable {
        public var day: LocalDay
        public var calendar: Calendar
        /// Planning never places anything before this instant (pass "now" when planning today).
        public var notBefore: Date
        /// Time already taken: fixed events, locked blocks, kept task blocks, transit…
        public var busy: [DateInterval]
        public var tasks: [PlannableTask]
        /// Check-in energy 1…5, or nil to use the settings' default.
        public var energy: Int?
        /// Task work already on this day that stays (past or locked blocks); counts against the budget.
        public var alreadyPlanned: TimeInterval
        public var settings: PlannerSettings

        public init(
            day: LocalDay,
            calendar: Calendar,
            notBefore: Date,
            busy: [DateInterval],
            tasks: [PlannableTask],
            energy: Int?,
            alreadyPlanned: TimeInterval = 0,
            settings: PlannerSettings = .default
        ) {
            self.day = day
            self.calendar = calendar
            self.notBefore = notBefore
            self.busy = busy
            self.tasks = tasks
            self.energy = energy
            self.alreadyPlanned = alreadyPlanned
            self.settings = settings
        }
    }

    public static func plan(_ input: Input) -> DayPlan {
        let minChunk = TimeInterval(input.settings.minimumChunkMinutes * 60)
        var budgetLeft = max(input.settings.budget(forEnergy: input.energy) - input.alreadyPlanned, 0)
        // Gaps below the minimum chunk are kept: a short task (or a task's last bit) can still use them.
        var spans = freeSpans(input, minGap: CalendarEngine.minimumDuration)

        var blocks: [PlannedBlock] = []
        var overflow: [PlannableTask] = []

        for var task in prioritized(input.tasks, now: input.notBefore) {
            var i = 0
            while task.remaining > 0, i < spans.count, budgetLeft > 0 {
                let chunk = min(task.remaining, spans[i].duration, budgetLeft)
                let finishesTask = chunk == task.remaining
                // A chunk must be at least the minimum, unless it's the task's last bit of work.
                guard chunk >= minChunk || (finishesTask && chunk >= CalendarEngine.minimumDuration) else {
                    i += 1
                    continue
                }
                let start = spans[i].start
                blocks.append(PlannedBlock(taskID: task.id, start: start, end: start.addingTimeInterval(chunk)))
                task.remaining -= chunk
                budgetLeft -= chunk
                spans[i] = DateInterval(start: start.addingTimeInterval(chunk), end: spans[i].end)
                if spans[i].duration < CalendarEngine.minimumDuration { spans.remove(at: i) }
            }
            if task.remaining > 0 { overflow.append(task) }
        }

        blocks.sort { $0.start < $1.start }
        return DayPlan(blocks: blocks, overflow: overflow)
    }

    /// Highest score first: energy cost, plus urgency as the deadline nears. Older tasks win ties.
    static func prioritized(_ tasks: [PlannableTask], now: Date) -> [PlannableTask] {
        func score(_ t: PlannableTask) -> Int {
            var s: Int
            switch t.energyCost {
            case .high: s = 100
            case .medium: s = 50
            case .low: s = 10
            }
            if let deadline = t.deadline {
                let daysLeft = deadline.timeIntervalSince(now) / 86_400
                if daysLeft <= 1 { s += 500 } else if daysLeft <= 3 { s += 200 } else if daysLeft <= 7 { s += 50 }
            }
            return s
        }
        return tasks.filter { $0.remaining > 0 }.sorted {
            let (a, b) = (score($0), score($1))
            return a != b ? a > b : $0.createdAt < $1.createdAt
        }
    }

    /// Planning "from now" starts at the next clean mark (14:52:59 → 14:55), never mid-minute.
    static func roundedUp(_ date: Date, toMinutes minutes: Int, calendar: Calendar) -> Date {
        let step = TimeInterval(minutes * 60)
        let hourStart = calendar.dateInterval(of: .hour, for: date)!.start
        let offset = date.timeIntervalSince(hourStart)
        return hourStart.addingTimeInterval((offset / step).rounded(.up) * step)
    }

    /// The day's planning window minus busy time, keeping only gaps of at least `minGap`.
    static func freeSpans(_ input: Input, minGap: TimeInterval) -> [DateInterval] {
        let cal = input.calendar
        let dayStart = input.day.start(in: cal)
        func time(_ minutes: Int) -> Date {
            if minutes >= 24 * 60 { return input.day.end(in: cal) }
            return cal.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: dayStart)!
        }
        let windowStart = max(time(input.settings.dayStartMinutes), roundedUp(input.notBefore, toMinutes: 5, calendar: cal))
        let windowEnd = time(input.settings.dayEndMinutes)
        guard windowEnd > windowStart else { return [] }

        var spans: [DateInterval] = []
        var cursor = windowStart
        for busy in input.busy.sorted(by: { $0.start < $1.start }) {
            if busy.end <= cursor { continue }
            if busy.start >= windowEnd { break }
            if busy.start > cursor { spans.append(DateInterval(start: cursor, end: busy.start)) }
            cursor = max(cursor, busy.end)
        }
        if cursor < windowEnd { spans.append(DateInterval(start: cursor, end: windowEnd)) }
        return spans.filter { $0.duration >= minGap }
    }
}
