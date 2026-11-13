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

/// The user's goal for a task (from a reminder's `when:` line, ticket 22).
public enum PlanningGoal: Equatable, Sendable {
    /// Must be planned today: ranks above every deadline.
    case today
    /// Must be done by the end of the week: treated like a deadline at `endsAt`.
    case week(endsAt: Date)
}

/// A task as the planner sees it: just what affects placement.
public struct PlannableTask: Equatable, Sendable {
    public var id: UUID
    public var remaining: TimeInterval
    public var energyCost: EnergyCost
    public var deadline: Date?
    public var createdAt: Date
    /// Travel time needed before the task's first block of the day (0 = none).
    public var transit: TimeInterval
    public var goal: PlanningGoal?
    /// When this kind of task tends to happen (ticket 20): placed there first when it's free.
    public var preferredWindow: PreferredWindow?

    public init(id: UUID, remaining: TimeInterval, energyCost: EnergyCost, deadline: Date?, createdAt: Date,
                transit: TimeInterval = 0, goal: PlanningGoal? = nil, preferredWindow: PreferredWindow? = nil) {
        self.id = id
        self.remaining = remaining
        self.energyCost = energyCost
        self.deadline = deadline
        self.createdAt = createdAt
        self.transit = transit
        self.goal = goal
        self.preferredWindow = preferredWindow
    }

    /// The deadline planning works to: the task's own, or the end of the week for a week goal.
    var effectiveDeadline: Date? {
        guard case .week(let endsAt) = goal else { return deadline }
        return deadline.map { min($0, endsAt) } ?? endsAt
    }
}

public struct PlannedBlock: Equatable, Sendable {
    public enum Kind: Sendable { case task, transit }

    public var taskID: UUID
    public var start: Date
    public var end: Date
    public var kind: Kind = .task
}

public struct DayPlan: Equatable, Sendable {
    public var blocks: [PlannedBlock]
    /// Tasks that did not fit, with the time still left to place.
    public var overflow: [PlannableTask]

    /// Task work planned (transit excluded).
    public var plannedDuration: TimeInterval {
        blocks.filter { $0.kind == .task }.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
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
            // Travel happens once, right before the task's first block of the day. It takes time
            // on the calendar but doesn't count against the energy budget.
            var lead = task.transit
            let window = task.preferredWindow?.interval(on: input.day, calendar: input.calendar)
            placing: while task.remaining > 0, budgetLeft > 0 {
                // Free time inside the preferred window first, then the rest of the day in order.
                for piece in candidates(spans, preferring: window) {
                    let available = piece.duration - lead
                    let chunk = min(task.remaining, available, budgetLeft)
                    let finishesTask = chunk == task.remaining
                    // A chunk must be at least the minimum, unless it's the task's last bit of work.
                    guard chunk >= minChunk || (finishesTask && chunk >= CalendarEngine.minimumDuration) else { continue }
                    let start = piece.start
                    if lead > 0 {
                        blocks.append(PlannedBlock(taskID: task.id, start: start, end: start.addingTimeInterval(lead), kind: .transit))
                    }
                    let taskStart = start.addingTimeInterval(lead)
                    blocks.append(PlannedBlock(taskID: task.id, start: taskStart, end: taskStart.addingTimeInterval(chunk)))
                    lead = 0
                    task.remaining -= chunk
                    budgetLeft -= chunk
                    take(DateInterval(start: start, end: taskStart.addingTimeInterval(chunk)), from: &spans)
                    continue placing
                }
                break   // nothing left that fits
            }
            if task.remaining > 0 { overflow.append(task) }
        }

        blocks.sort { $0.start < $1.start }
        return DayPlan(blocks: blocks, overflow: overflow)
    }

    /// Highest score first: a today goal above all, then energy cost plus urgency as the deadline
    /// (or a week goal's Sunday) nears. Older tasks win ties.
    static func prioritized(_ tasks: [PlannableTask], now: Date) -> [PlannableTask] {
        func score(_ t: PlannableTask) -> Int {
            var s: Int
            switch t.energyCost {
            case .high: s = 100
            case .medium: s = 50
            case .low: s = 10
            }
            if t.goal == .today { s += 10_000 }
            if let deadline = t.effectiveDeadline {
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

    /// Free spans to try, in order: the parts inside `window` first, then every other part by time.
    /// Without a window, simply the spans in time order.
    static func candidates(_ spans: [DateInterval], preferring window: DateInterval?) -> [DateInterval] {
        guard let window else { return spans }
        var inside: [DateInterval] = [], outside: [DateInterval] = []
        for span in spans {
            if let overlap = span.intersection(with: window), overlap.duration >= CalendarEngine.minimumDuration {
                inside.append(overlap)
                if overlap.start > span.start { outside.append(DateInterval(start: span.start, end: overlap.start)) }
                if overlap.end < span.end { outside.append(DateInterval(start: overlap.end, end: span.end)) }
            } else {
                outside.append(span)
            }
        }
        return inside + outside.filter { $0.duration >= CalendarEngine.minimumDuration }.sorted { $0.start < $1.start }
    }

    /// Removes `used` from the free spans, keeping what's left on either side if it's usable.
    static func take(_ used: DateInterval, from spans: inout [DateInterval]) {
        guard let index = spans.firstIndex(where: { $0.start <= used.start && used.end <= $0.end }) else { return }
        let span = spans.remove(at: index)
        let rest = [DateInterval(start: span.start, end: used.start), DateInterval(start: used.end, end: span.end)]
            .filter { $0.duration >= CalendarEngine.minimumDuration }
        spans.insert(contentsOf: rest, at: index)
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
