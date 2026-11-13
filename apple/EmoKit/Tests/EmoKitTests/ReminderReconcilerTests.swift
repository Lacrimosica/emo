import Foundation
import SwiftData
import Testing
@testable import EmoKit

@MainActor
@Suite struct ReminderReconcilerTests {
    let container = try! EmoStore.makeContainer(.inMemory)
    var context: ModelContext { container.mainContext }
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Rome")!
        return c
    }()
    let day = LocalDay(year: 2026, month: 11, day: 13)
    var reconciler: ReminderReconciler { ReminderReconciler(context: context, calendar: calendar) }

    func at(_ hour: Int) -> Date { calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day.start(in: calendar))! }
    func snap(_ reminders: [ExternalReminder], sources: Set<String> = ["home"]) -> ReminderSnapshot {
        ReminderSnapshot(provider: "apple-reminders", sources: sources, reminders: reminders)
    }
    func r(_ id: String, _ title: String, due: Date? = nil, done: Bool = false, list: String = "home") -> ExternalReminder {
        ExternalReminder(externalID: id, sourceID: list, title: title, due: due, isCompleted: done)
    }
    func open() throws -> [TaskItem] { try Backlog(context: context).openTasks() }

    @Test func openRemindersBecomeTasksFlaggedForReview() throws {
        let result = try reconciler.apply(snap([r("1", "Buy stamps", due: at(18))]), now: at(8))
        #expect(result.added == 1)
        let task = try #require(try open().first)
        #expect(task.name == "Buy stamps" && task.deadline == at(18) && task.needsReview)
        #expect(task.estimatedHours == ReminderReconciler.defaultEstimateHours)
    }

    @Test func resyncIsIdempotent() throws {
        try reconciler.apply(snap([r("1", "Buy stamps")]), now: at(8))
        let again = try reconciler.apply(snap([r("1", "Buy stamps")]), now: at(9))
        #expect(!again.changed)
        #expect(try open().count == 1)
    }

    @Test func upstreamEditsUpdateTitleAndDueButKeepUserSizing() throws {
        try reconciler.apply(snap([r("1", "Buy stamps")]), now: at(8))
        let task = try #require(try open().first)
        var draft = TaskDraft(task)
        draft.estimatedHours = 2
        draft.energyCost = .high
        try TaskLifecycle(context: context, calendar: calendar).update(task, with: draft, now: at(8))
        #expect(!task.needsReview)   // the user reviewed it

        let result = try reconciler.apply(snap([r("1", "Buy stamps & envelopes", due: at(17))]), now: at(9))
        #expect(result.updated == 1)
        #expect(task.name == "Buy stamps & envelopes" && task.deadline == at(17))
        #expect(task.estimatedHours == 2 && task.energyCost == .high && !task.needsReview)
    }

    @Test func completingUpstreamCompletesTheTaskAndFreesItsPlan() throws {
        try CheckIns(context: context).record(mood: 3, energy: 5, for: day)
        try reconciler.apply(snap([r("1", "Call bank")]), now: at(7))
        try DayPlanning(context: context, calendar: calendar).plan(day, now: at(7))
        #expect(try CalendarEngine(context: context).events(on: day, calendar: calendar).count == 1)

        let result = try reconciler.apply(snap([r("1", "Call bank", done: true)]), now: at(8))
        #expect(result.completed == 1)
        #expect(try open().isEmpty)
        #expect(try CalendarEngine(context: context).events(on: day, calendar: calendar).isEmpty)
    }

    @Test func alreadyCompletedRemindersAreNotImported() throws {
        let result = try reconciler.apply(snap([r("1", "Old thing", done: true)]), now: at(8))
        #expect(result.added == 0)
        #expect(try context.fetchCount(FetchDescriptor<TaskItem>()) == 0)
    }

    @Test func deletedUpstreamRemovesTheOpenTask() throws {
        try reconciler.apply(snap([r("1", "A"), r("2", "B")]), now: at(8))
        let result = try reconciler.apply(snap([r("1", "A")]), now: at(9))
        #expect(result.removed == 1)
        #expect(try open().map(\.name) == ["A"])
    }

    @Test func remindersFromUncoveredListsAreLeftAloneAndDeselectingRemovesThem() throws {
        try reconciler.apply(snap([r("1", "Home thing"), r("2", "Work thing", list: "work")], sources: ["home", "work"]), now: at(8))
        try reconciler.apply(snap([r("1", "Home thing")], sources: ["home"]), now: at(9))
        #expect(try open().count == 2)
        try reconciler.removeAll(provider: "apple-reminders", keeping: ["home"], now: at(10))
        #expect(try open().map(\.name) == ["Home thing"])
    }

    @Test func turningOffKeepsCompletedHistory() throws {
        try reconciler.apply(snap([r("1", "Done one"), r("2", "Open one")]), now: at(8))
        try reconciler.apply(snap([r("1", "Done one", done: true), r("2", "Open one")]), now: at(9))
        try reconciler.removeAll(provider: "apple-reminders", now: at(10))
        #expect(try open().isEmpty)
        #expect(try context.fetchCount(FetchDescriptor<TaskItem>()) == 1)   // the completed one
        #expect(try context.fetchCount(FetchDescriptor<ExternalLink>()) == 0)
    }

    @Test func taskDeletedInEmoIsReimportedWhileTheReminderIsOpen() throws {
        try reconciler.apply(snap([r("1", "Persistent")]), now: at(8))
        try TaskLifecycle(context: context, calendar: calendar).delete(try #require(try open().first), now: at(8))
        let result = try reconciler.apply(snap([r("1", "Persistent")]), now: at(9))
        #expect(result.added == 1)
        #expect(try open().count == 1)
    }
}

@Suite struct ReminderDueDateTests {
    @Test func dateOnlyDueMeansEndOfDay() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Rome")!
        let dateOnly = AppleRemindersSource.dueDate(DateComponents(year: 2026, month: 11, day: 20), calendar: cal)!
        #expect(cal.component(.hour, from: dateOnly) == 23)
        let timed = AppleRemindersSource.dueDate(DateComponents(year: 2026, month: 11, day: 20, hour: 9, minute: 30), calendar: cal)!
        #expect(cal.component(.hour, from: timed) == 9)
        #expect(AppleRemindersSource.dueDate(nil, calendar: cal) == nil)
    }
}
