import Foundation
import SwiftData
import Testing
@testable import EmoKit

/// Ticket 31: ongoing tasks with a weekly target.
@MainActor
@Suite struct OngoingTaskTests {
    let container = try! EmoStore.makeContainer(.inMemory)
    var context: ModelContext { container.mainContext }
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Rome")!
        return c
    }()
    /// Monday 9 November 2026.
    let monday = LocalDay(year: 2026, month: 11, day: 9)
    func day(_ offset: Int) -> LocalDay { monday.adding(days: offset, calendar: calendar) }
    func at(_ hour: Int, on d: LocalDay) -> Date {
        calendar.date(bySettingHour: hour, minute: 0, second: 0, of: d.start(in: calendar))!
    }

    var planning: DayPlanning { DayPlanning(context: context, calendar: calendar) }
    var schedule: OngoingSchedule { OngoingSchedule(context: context, calendar: calendar) }
    var lifecycle: TaskLifecycle { TaskLifecycle(context: context, calendar: calendar) }

    func ongoing(_ name: String = "Study Swift", sessions: Int = 3, hours: Double = 1) throws -> TaskItem {
        var draft = TaskDraft(name: name)
        draft.isOngoing = true
        draft.sessionsPerWeek = sessions
        draft.sessionHours = hours
        return try Backlog(context: context).add(draft)
    }

    func blockDays(_ task: TaskItem) throws -> [LocalDay] {
        try CalendarEngine(context: context).events(forTask: task.id)
            .filter { $0.kind == .taskBlock }.map { LocalDay($0.start, calendar: calendar) }.sorted()
    }

    @Test func aSessionIsPlannedLikeATaskOfOneSessionsLength() throws {
        let task = try ongoing(hours: 1.5)
        #expect(task.estimatedHours == 1.5 && task.recurrence == .none)
        try planning.plan(monday, now: at(8, on: monday))
        let blocks = try CalendarEngine(context: context).events(on: monday, calendar: calendar).filter { $0.taskID == task.id }
        #expect(blocks.reduce(0) { $0 + $1.duration } == 1.5 * 3600)
    }

    @Test func sessionsAreSpreadWithoutBackToBackDays() throws {
        let task = try ongoing(sessions: 3)
        for offset in 0..<7 { try planning.plan(day(offset), now: at(8, on: day(offset))) }
        // (Planning Sunday also plans Monday, which starts a new week with a fresh target.)
        #expect(try blockDays(task).filter { $0 < day(7) } == [day(0), day(2), day(4)])
    }

    @Test func backToBackDaysAreUsedWhenTheWeekRunsOut() throws {
        let task = try ongoing(sessions: 3)
        // From Friday: three sessions left, three days left.
        for offset in 4..<7 { try planning.plan(day(offset), now: at(8, on: day(offset))) }
        #expect(try blockDays(task).filter { $0 < day(7) } == [day(4), day(5), day(6)])
        #expect(try blockDays(task).contains(day(7)))   // the next week starts over
    }

    @Test func aMetTargetPlansNothingMoreThatWeek() throws {
        let task = try ongoing(sessions: 2)
        try lifecycle.logSession(task, on: day(0), now: at(20, on: day(0)))
        try lifecycle.logSession(task, on: day(2), now: at(20, on: day(2)))
        #expect(try schedule.timeDue(task, on: day(4)) == nil)
        // Next week the target starts over.
        #expect(try schedule.timeDue(task, on: day(7)) == 3600)
    }

    @Test func loggingASessionKeepsTheTaskOpenAndCountsTowardTheTarget() throws {
        let task = try ongoing(sessions: 3)
        try planning.plan(monday, now: at(8, on: monday))
        try lifecycle.logSession(task, on: monday, now: at(20, on: monday))
        #expect(!task.isCompleted)
        #expect(try schedule.sessionsDone(task, inWeekOf: monday).count == 1)
        #expect(try schedule.timeDue(task, on: monday) == nil)   // one a day
    }

    @Test func aSkippedSessionMovesToAnotherDayThisWeek() throws {
        let task = try ongoing(sessions: 1)
        try planning.plan(monday, now: at(8, on: monday))
        #expect(try blockDays(task) == [monday])
        try lifecycle.skip(task, on: monday, now: at(9, on: monday))
        #expect(try blockDays(task) == [day(1)])
    }

    @Test func sessionsStayWithinTheEnergyBudget() throws {
        try CheckIns(context: context).record(mood: 3, energy: 1, for: monday)   // 2h budget
        let task = try ongoing(sessions: 3, hours: 3)
        try planning.plan(monday, now: at(8, on: monday))
        let planned = try CalendarEngine(context: context).events(on: monday, calendar: calendar)
            .filter { $0.taskID == task.id && $0.kind == .taskBlock }.reduce(0) { $0 + $1.duration }
        #expect(planned == 2 * 3600)
    }

    @Test func ongoingIsReadFromReminderNotesAndNeedsNoReview() throws {
        let reconciler = ReminderReconciler(context: context, calendar: calendar)
        let reminder = ExternalReminder(externalID: "1", sourceID: "home", title: "Study Swift",
                                        list: .infer(fromTitle: "NA - Personal"), notes: "ongoing: 3x/week 45m")
        try reconciler.apply(ReminderSnapshot(provider: "apple-reminders", sources: ["home"], reminders: [reminder]),
                             now: at(8, on: monday))
        let task = try #require(try Backlog(context: context).openTasks().first)
        #expect(task.isOngoing && task.sessionsPerWeek == 3 && task.sessionHours == 0.75 && !task.needsReview)
        #expect(task.ongoingNotesValue == "3x/week 45m")
    }

    @Test func completingTheReminderEndsTheOngoingTaskForGood() throws {
        let reconciler = ReminderReconciler(context: context, calendar: calendar)
        var reminder = ExternalReminder(externalID: "1", sourceID: "home", title: "Study Swift",
                                        list: .infer(fromTitle: "NA - Personal"), notes: "ongoing")
        let snap = { ReminderSnapshot(provider: "apple-reminders", sources: ["home"], reminders: [reminder]) }
        try reconciler.apply(snap(), now: at(8, on: monday))
        let task = try #require(try Backlog(context: context).openTasks().first)
        try lifecycle.logSession(task, on: monday, now: at(9, on: monday))
        reminder.isCompleted = true
        try reconciler.apply(snap(), now: at(10, on: monday))
        #expect(task.isCompleted)
        #expect(try schedule.sessionsDone(task, inWeekOf: monday).count == 1)   // history stays
    }
}
