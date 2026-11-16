import Foundation
import SwiftData
import Testing
@testable import EmoKit

/// Ticket 34: routine lists as one daily checklist block.
@MainActor
@Suite struct RoutineChecklistTests {
    let container = try! EmoStore.makeContainer(.inMemory)
    var context: ModelContext { container.mainContext }
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Rome")!
        return c
    }()
    let day = LocalDay(year: 2026, month: 11, day: 16)   // a Monday
    var reconciler: ReminderReconciler { ReminderReconciler(context: context, calendar: calendar) }
    var checklists: RoutineChecklist { RoutineChecklist(context: context, calendar: calendar) }

    func at(_ hour: Int, on d: LocalDay? = nil) -> Date {
        calendar.date(bySettingHour: hour, minute: 0, second: 0, of: (d ?? day).start(in: calendar))!
    }
    func snap(_ reminders: [ExternalReminder]) -> ReminderSnapshot {
        ReminderSnapshot(provider: "apple-reminders", sources: ["daily", "home"], reminders: reminders)
    }
    func item(_ id: String, _ title: String, doneAt: Date? = nil) -> ExternalReminder {
        ExternalReminder(externalID: id, sourceID: "daily", title: title, isCompleted: doneAt != nil, completedAt: doneAt,
                         list: .infer(fromTitle: "CHECKLIST DAILY"))
    }
    let morning = ["Meds", "Water plants", "Make bed"]
    func importChecklist(_ titles: [String]? = nil) throws {
        try reconciler.apply(snap((titles ?? morning).enumerated().map { item("\($0.offset)", $0.element) }), now: at(7))
    }
    func open() throws -> [TaskItem] { try Backlog(context: context).openTasks() }
    func checklist() throws -> TaskItem { try #require(try open().first { $0.isChecklist }) }
    func blocks(_ task: TaskItem) throws -> [CalendarEvent] {
        try CalendarEngine(context: context).events(forTask: task.id).filter { $0.kind == .taskBlock }
    }

    @Test func routineItemsBecomeOneDailyChecklist() throws {
        try importChecklist()
        let list = try checklist()
        #expect(list.name == RoutineChecklist.defaultName)
        #expect(list.isOngoing && list.sessionsPerWeek == 7)
        #expect(abs(list.sessionHours - 15.0 / 60) < 0.0001)   // 3 × 5 min
        let items = try open().filter(\.isRoutineItem)
        #expect(items.count == 3 && items.allSatisfy { !$0.needsReview && !$0.isPlannable(on: day) })
        #expect(try !open().contains(where: \.looksVague))   // "Meds" is a fine checklist item
    }

    @Test func planningPutsOneChecklistBlockOnTheDay() throws {
        try importChecklist()
        try DayPlanning(context: context, calendar: calendar).plan(day, now: at(8))
        let list = try checklist()
        #expect(try blocks(list).filter { LocalDay($0.start, calendar: calendar) == day }.map(\.duration) == [15 * 60])
        for item in try open().filter(\.isRoutineItem) { #expect(try blocks(item).isEmpty) }
        // Every day, not spread out like a 2×/week task.
        #expect(try !blocks(list).filter { LocalDay($0.start, calendar: calendar) == day.adding(days: 1, calendar: calendar) }.isEmpty)
    }

    @Test func theChecklistFollowsItsItems() throws {
        try importChecklist()
        try importChecklist(morning + ["Stretch", "Journal"])
        #expect(abs(try checklist().sessionHours - 25.0 / 60) < 0.0001)
        try reconciler.apply(snap([]), now: at(9))   // list emptied
        #expect(try !open().contains { $0.isChecklist })
    }

    @Test func eachRoutineAreaGetsItsOwnChecklist() throws {
        try reconciler.apply(snap([
            item("1", "Meds"),
            ExternalReminder(externalID: "2", sourceID: "home", title: "Feed cat", list: .infer(fromTitle: "ROUTINE - Home")),
        ]), now: at(7))
        #expect(Set(try open().filter(\.isChecklist).map(\.name)) == [RoutineChecklist.defaultName, "Checklist: Home"])
    }

    @Test func tickingAnItemInEmoIsDoneForTodayOnly() throws {
        try importChecklist()
        let meds = try #require(try open().first { $0.name == "Meds" })
        try TaskLifecycle(context: context, calendar: calendar).complete(meds, now: at(9))
        #expect(!meds.isCompleted)
        #expect(try checklists.isDone(meds, on: day))
        #expect(try !checklists.isDone(meds, on: day.adding(days: 1, calendar: calendar)))
    }

    @Test func allItemsDoneCompletesTheDaysChecklist() throws {
        try importChecklist()
        try DayPlanning(context: context, calendar: calendar).plan(day, now: at(8))
        let list = try checklist()
        let lifecycle = TaskLifecycle(context: context, calendar: calendar)
        for item in try open().filter(\.isRoutineItem) { try lifecycle.complete(item, now: at(8)) }
        #expect(try checklists.isDone(list, on: day))
        #expect(try blocks(list).filter { LocalDay($0.start, calendar: calendar) == day && $0.start >= at(8) }.isEmpty)
        #expect(!list.isCompleted)
    }

    @Test func aCompletionInRemindersCountsForTheDayItWasTicked() throws {
        try importChecklist()
        let yesterday = day.adding(days: -1, calendar: calendar)
        try reconciler.apply(snap([item("0", "Meds", doneAt: at(21, on: yesterday)), item("1", "Water plants"), item("2", "Make bed")]),
                             now: at(7))
        let meds = try #require(try open().first { $0.name == "Meds" })
        #expect(try checklists.isDone(meds, on: yesterday))
        #expect(try !checklists.isDone(meds, on: day))
        // Seen again on later syncs: still one session.
        try reconciler.apply(snap([item("0", "Meds", doneAt: at(21, on: yesterday)), item("1", "Water plants"), item("2", "Make bed")]),
                             now: at(8))
        #expect(try context.fetchCount(FetchDescriptor<TaskSession>()) == 1)
    }
}
