import Foundation
import SwiftData
import Testing
@testable import EmoKit

@MainActor
@Suite struct DayPlanningTests {
    let container = try! EmoStore.makeContainer(.inMemory)
    var context: ModelContext { container.mainContext }
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Rome")!
        return c
    }()
    let day = LocalDay(year: 2026, month: 11, day: 13)
    var tomorrow: LocalDay { day.adding(days: 1, calendar: calendar) }

    var planning: DayPlanning { DayPlanning(context: context, calendar: calendar) }
    var engine: CalendarEngine { CalendarEngine(context: context) }

    func at(_ hour: Int, _ minute: Int = 0, on d: LocalDay? = nil) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: (d ?? day).start(in: calendar))!
    }

    @discardableResult
    func addTask(_ name: String, hours: Double, cost: EnergyCost = .medium, created: Int = 0) throws -> TaskItem {
        try Backlog(context: context).add(
            TaskDraft(name: name, estimatedHours: hours, energyCost: cost),
            now: Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + created))
        )
    }

    func taskBlocks(on d: LocalDay) throws -> [CalendarEvent] {
        try engine.events(on: d, calendar: calendar).filter { $0.kind == .taskBlock }
    }

    @Test func planningFillsTheDayAroundFixedEvents() throws {
        try CheckIns(context: context).record(mood: 3, energy: 5, for: day)
        try engine.createFixedEvent(title: "Dentist", start: at(10), end: at(11))
        let report = try addTask("Report", hours: 2, cost: .high)

        let summary = try planning.plan(day, now: at(7))

        let blocks = try taskBlocks(on: day)
        #expect(blocks.map(\.start) == [at(9), at(11)])
        #expect(blocks.map(\.end) == [at(10), at(12)])
        #expect(blocks.allSatisfy { $0.taskID == report.id && $0.title == "Report" && $0.origin == .local })
        #expect(summary.planned == .init(day: day, planned: 2 * 3600, taskCount: 1))
        #expect(summary.spill.planned == 0)
        #expect(summary.unplacedTaskCount == 0)
    }

    @Test func replanningReplacesAutoBlocksButKeepsFixedAndLocked() throws {
        try CheckIns(context: context).record(mood: 3, energy: 5, for: day)
        let fixed = try engine.createFixedEvent(title: "Standup", start: at(9), end: at(9, 30))
        let task = try addTask("Deep work", hours: 3)
        try planning.plan(day, now: at(7))

        // User locks the first block, then plans again.
        let firstBlock = try #require(try taskBlocks(on: day).first)
        firstBlock.isLocked = true
        try context.save()
        let lockedRange = (firstBlock.start, firstBlock.end)

        try planning.plan(day, now: at(7))

        let events = try engine.events(on: day, calendar: calendar)
        #expect(events.contains { $0.id == fixed.id })
        #expect(events.contains { $0.id == firstBlock.id && ($0.start, $0.end) == lockedRange })
        let total = try taskBlocks(on: day).filter { $0.taskID == task.id }.reduce(0) { $0 + $1.duration }
        #expect(total == 3 * 3600)   // no double-booking across re-plans
    }

    @Test func pastBlocksTodayAreKeptAndCountTowardTheTask() throws {
        try CheckIns(context: context).record(mood: 3, energy: 5, for: day)
        try addTask("Essay", hours: 2)
        try planning.plan(day, now: at(7))          // 9:00–11:00

        try planning.plan(day, now: at(10))         // 9:00–10:00 has started; keep it
        let blocks = try taskBlocks(on: day)
        #expect(blocks.map(\.start) == [at(9)])
        #expect(blocks.first?.end == at(11))
    }

    @Test func overflowSpillsIntoTomorrowWithDefaultEnergy() throws {
        try CheckIns(context: context).record(mood: 3, energy: 1, for: day)   // 2h budget
        try addTask("Big", hours: 4, cost: .high)

        let summary = try planning.plan(day, now: at(7))

        #expect(summary.planned.planned == 2 * 3600)
        #expect(summary.spill == .init(day: tomorrow, planned: 2 * 3600, taskCount: 1))
        #expect(try taskBlocks(on: tomorrow).first?.start == at(9, on: tomorrow))
    }

    @Test func spillDoesNotWipeTomorrowsWorkForOtherTasks() throws {
        try CheckIns(context: context).record(mood: 3, energy: 1, for: day)   // 2h budget today
        try addTask("A", hours: 2, cost: .high, created: 0)
        try addTask("B", hours: 2, cost: .medium, created: 1)

        try planning.plan(day, now: at(7))
        try planning.plan(day, now: at(7))   // idempotent: same result the second time

        let today = try taskBlocks(on: day), next = try taskBlocks(on: tomorrow)
        #expect(today.map(\.title) == ["A"])
        #expect(next.map(\.title) == ["B"])
    }

    @Test func taskTimeOnOtherDaysIsNotPlannedAgain() throws {
        try CheckIns(context: context).record(mood: 3, energy: 5, for: day)
        let task = try addTask("Course", hours: 3)
        // An hour already done yesterday (a past block, not replaceable).
        let yesterday = day.adding(days: -1, calendar: calendar)
        try engine.replacePlannedTaskBlocks(on: yesterday, from: at(0, on: yesterday),
                                            with: [(task, at(9, on: yesterday), at(10, on: yesterday), .taskBlock)],
                                            calendar: calendar)

        try planning.plan(day, now: at(7))
        #expect(try taskBlocks(on: day).reduce(0) { $0 + $1.duration } == 2 * 3600)
    }

    @Test func completedTasksAreNotPlanned() throws {
        try CheckIns(context: context).record(mood: 3, energy: 5, for: day)
        let done = try addTask("Done", hours: 1)
        done.completedAt = at(6)
        try context.save()

        try planning.plan(day, now: at(7))
        #expect(try taskBlocks(on: day).isEmpty)
    }

    @Test func transitIsWrittenAndReplacedWithItsTask() throws {
        try CheckIns(context: context).record(mood: 3, energy: 5, for: day)
        let errand = try Backlog(context: context).add(
            TaskDraft(name: "Post office", estimatedHours: 0.5, requiresTransit: true, transitMinutes: 20))

        try planning.plan(day, now: at(7))
        let first = try engine.events(on: day, calendar: calendar)
        #expect(first.map(\.kind) == [.transit, .taskBlock])
        #expect(first.map(\.title) == ["Transit → Post office", "Post office"])
        #expect(first.map(\.start) == [at(9), at(9, 20)])
        #expect(first.allSatisfy { $0.taskID == errand.id })

        try planning.plan(day, now: at(7))   // re-plan replaces both, no duplicates
        #expect(try engine.events(on: day, calendar: calendar).count == 2)
    }

    @Test func manualTransitIsNeverReplacedByPlanning() throws {
        try CheckIns(context: context).record(mood: 3, energy: 5, for: day)
        let manual = try engine.createTransit(start: at(9), duration: 30 * 60, note: "Drive to office")
        try addTask("Work", hours: 1)

        try planning.plan(day, now: at(7))
        let events = try engine.events(on: day, calendar: calendar)
        #expect(events.first?.id == manual.id)
        #expect(events.first?.title == "Drive to office")
        #expect(events.last?.start == at(9, 30))   // planned around it
    }

    @Test func completingATaskRemovesItsTransit() throws {
        try CheckIns(context: context).record(mood: 3, energy: 5, for: day)
        let errand = try Backlog(context: context).add(
            TaskDraft(name: "Pharmacy", estimatedHours: 0.5, requiresTransit: true, transitMinutes: 15))
        try planning.plan(day, now: at(7))

        try TaskLifecycle(context: context, calendar: calendar).complete(errand, now: at(8))
        #expect(try engine.events(on: day, calendar: calendar).isEmpty)
    }

    @Test func planningAfterDayEndPushesEverythingToTomorrow() throws {
        try addTask("Late", hours: 1)
        let summary = try planning.plan(day, now: at(23))
        #expect(summary.planned.planned == 0)
        #expect(summary.spill.planned == 3600)
    }
}

/// Ticket 22: `when: today` / `when: week` goals from reminder notes.
@MainActor
@Suite struct PlanningGoalTests {
    let container = try! EmoStore.makeContainer(.inMemory)
    var context: ModelContext { container.mainContext }
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Rome")!
        return c
    }()
    /// Friday 13 November 2026.
    let day = LocalDay(year: 2026, month: 11, day: 13)

    func at(_ hour: Int, on d: LocalDay? = nil) -> Date {
        calendar.date(bySettingHour: hour, minute: 0, second: 0, of: (d ?? day).start(in: calendar))!
    }

    func task(_ name: String, hours: Double, cost: EnergyCost = .medium, deadline: Date? = nil,
              when goal: ReminderNotes.When? = nil, seen: LocalDay? = nil) throws -> TaskItem {
        let t = try Backlog(context: context).add(TaskDraft(name: name, estimatedHours: hours, energyCost: cost, deadline: deadline))
        t.noteWhenGoal(goal, seenOn: seen ?? day)
        return t
    }

    func firstPlanned(on d: LocalDay) throws -> String? {
        try CalendarEngine(context: context).events(on: d, calendar: calendar)
            .filter { $0.kind == .taskBlock }.min { $0.start < $1.start }?.title
    }

    @Test func todayGoalBeatsADeadline() throws {
        try CheckIns(context: context).record(mood: 3, energy: 1, for: day)   // 2h budget: room for one
        try task("Urgent report", hours: 2, cost: .high, deadline: at(18))
        try task("Send CV", hours: 2, cost: .low, when: .today)
        let summary = try DayPlanning(context: context, calendar: calendar).plan(day, now: at(8))
        #expect(try firstPlanned(on: day) == "Send CV")
        #expect(summary.unmetTodayGoals.isEmpty)
    }

    @Test func aTodayGoalThatDoesntFitIsReported() throws {
        try CheckIns(context: context).record(mood: 3, energy: 1, for: day)   // 2h budget
        try task("Send CV", hours: 3, when: .today)
        let summary = try DayPlanning(context: context, calendar: calendar).plan(day, now: at(8))
        #expect(summary.unmetTodayGoals == ["Send CV"])
    }

    @Test func staleTodayGoalDecaysToNormalPriority() throws {
        let yesterday = day.adding(days: -1, calendar: calendar)
        let t = try task("Send CV", hours: 1, when: .today, seen: yesterday)
        #expect(t.goal(on: yesterday, calendar: calendar) == .today)
        #expect(t.goal(on: day, calendar: calendar) == nil)
    }

    @Test func weekGoalActsLikeASundayDeadline() throws {
        let t = try task("Portfolio", hours: 1, when: .week)   // seen Friday
        let sunday = LocalDay(year: 2026, month: 11, day: 15)
        #expect(t.goal(on: day, calendar: calendar) == .week(endsAt: sunday.end(in: calendar)))
        #expect(t.goal(on: sunday, calendar: calendar) != nil)
        #expect(t.goal(on: sunday.adding(days: 1, calendar: calendar), calendar: calendar) == nil)

        // On Friday a week goal ranks like a task due in two days: ahead of an older, undated one.
        let undated = PlannableTask(id: UUID(), remaining: 3600, energyCost: .medium, deadline: nil, createdAt: .distantPast)
        let weekly = PlannableTask(id: t.id, remaining: 3600, energyCost: .medium, deadline: nil, createdAt: .now,
                                   goal: t.goal(on: day, calendar: calendar))
        #expect(DayPlanner.prioritized([undated, weekly], now: at(8)).first?.id == t.id)
    }

    @Test func seenDayOnlyChangesWhenTheGoalDoes() throws {
        let t = try task("Send CV", hours: 1, when: .today)
        t.noteWhenGoal(.today, seenOn: day.adding(days: 1, calendar: calendar))
        #expect(t.whenSeenDayKey == day.key)
        t.noteWhenGoal(nil, seenOn: day)
        #expect(t.whenGoalRaw == nil && t.whenSeenDayKey == nil)
    }

    @Test func goalsAreReadFromReminderNotesOnSync() throws {
        let reconciler = ReminderReconciler(context: context, calendar: calendar)
        let reminder = ExternalReminder(externalID: "1", sourceID: "home", title: "Send CV",
                                        list: .infer(fromTitle: "NA - Personal"), notes: "when: today")
        try reconciler.apply(ReminderSnapshot(provider: "apple-reminders", sources: ["home"], reminders: [reminder]), now: at(9))
        let t = try #require(try Backlog(context: context).openTasks().first)
        #expect(t.goal(on: day, calendar: calendar) == .today)
    }
}
