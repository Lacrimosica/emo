import Foundation
import SwiftData
import Testing
@testable import EmoKit

/// Stands in for Reminders.app's completion: which reminders are ticked and which repeat.
@MainActor
final class FakeCompletionWriter: ReminderCompletionWriting {
    var completed: Set<String> = []
    var repeating: Set<String> = []
    var existing: Set<String> = []
    var failing = false
    private(set) var saves = 0

    func setCompleted(externalID: String, _ done: Bool, onlyIfRepeating: Bool) async throws -> Bool {
        if failing { throw LLMError.transport("Reminders is unavailable") }
        guard existing.contains(externalID) else { return false }
        if onlyIfRepeating, !repeating.contains(externalID) { return false }
        guard completed.contains(externalID) != done else { return true }
        if done { completed.insert(externalID) } else { completed.remove(externalID) }
        saves += 1
        return true
    }
}

/// Ticket 35: ticking in Emo ticks the reminder; syncs re-plan days already planned.
@MainActor
@Suite struct ReminderCompletionWriteBackTests {
    let container = try! EmoStore.makeContainer(.inMemory)
    var context: ModelContext { container.mainContext }
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Rome")!
        return c
    }()
    let day = LocalDay(year: 2026, month: 11, day: 16)
    let writer = FakeCompletionWriter()

    func at(_ hour: Int, on d: LocalDay? = nil) -> Date {
        calendar.date(bySettingHour: hour, minute: 0, second: 0, of: (d ?? day).start(in: calendar))!
    }
    var reconciler: ReminderReconciler { ReminderReconciler(context: context, calendar: calendar) }
    var lifecycle: TaskLifecycle { TaskLifecycle(context: context, calendar: calendar) }
    var writeBack: ReminderCompletionWriteBack { ReminderCompletionWriteBack(context: context) }

    func snap(_ reminders: [ExternalReminder]) -> ReminderSnapshot {
        ReminderSnapshot(provider: "apple-reminders", sources: ["home", "daily"], reminders: reminders)
    }
    func action(_ id: String = "r1", _ title: String = "Send CV", done: Date? = nil) -> ExternalReminder {
        ExternalReminder(externalID: id, sourceID: "home", title: title, isCompleted: done != nil, completedAt: done,
                         list: .infer(fromTitle: "NA - Personal"))
    }
    func routine(_ id: String, _ title: String = "Meds", done: Date? = nil) -> ExternalReminder {
        ExternalReminder(externalID: id, sourceID: "daily", title: title, isCompleted: done != nil, completedAt: done,
                         list: .infer(fromTitle: "CHECKLIST DAILY"))
    }
    func task(_ name: String) throws -> TaskItem {
        try #require(try context.fetch(FetchDescriptor<TaskItem>()).first { $0.name == name && !$0.isChecklist })
    }

    @Test func tickingInEmoTicksTheReminder() async throws {
        try reconciler.apply(snap([action()]), now: at(8))
        writer.existing = ["r1"]
        try lifecycle.complete(try task("Send CV"), now: at(9))
        let result = try await writeBack.flush(using: writer)
        #expect(result.written == 1)
        #expect(writer.completed == ["r1"])
        #expect(try writeBack.pendingTasks().isEmpty)
        // The next sync sees it ticked and changes nothing.
        let sync = try reconciler.apply(snap([action(done: at(9))]), now: at(10))
        #expect(!sync.changed)
    }

    @Test func completionsFromASyncAreNotWrittenBack() throws {
        try reconciler.apply(snap([action()]), now: at(8))
        try reconciler.apply(snap([action(done: at(9))]), now: at(10))
        #expect(try task("Send CV").isCompleted)
        #expect(try writeBack.pendingTasks().isEmpty)
    }

    @Test func aFailedWriteIsRetried() async throws {
        try reconciler.apply(snap([action()]), now: at(8))
        writer.existing = ["r1"]
        try lifecycle.complete(try task("Send CV"), now: at(9))
        writer.failing = true
        #expect(try await writeBack.flush(using: writer).failed == 1)
        // A sync in between doesn't undo Emo's tick.
        try reconciler.apply(snap([action()]), now: at(10))
        #expect(try task("Send CV").isCompleted)
        writer.failing = false
        #expect(try await writeBack.flush(using: writer).written == 1)
        #expect(writer.completed == ["r1"])
    }

    @Test func tasksWithoutAReminderAreDropped() async throws {
        let mine = try Backlog(context: context).add(TaskDraft(name: "Emo-only", estimatedHours: 1))
        try lifecycle.complete(mine, now: at(9))
        #expect(try await writeBack.flush(using: writer).dropped == 1)
        #expect(writer.saves == 0)
    }

    @Test func reopeningInEmoBeatsAStaleTickUpstream() async throws {
        try reconciler.apply(snap([action()]), now: at(8))
        writer.existing = ["r1"]
        let t = try task("Send CV")
        try lifecycle.complete(t, now: at(9))
        try await writeBack.flush(using: writer)
        try lifecycle.reopen(t)
        try reconciler.apply(snap([action(done: at(9))]), now: at(10))   // not written yet
        #expect(!t.isCompleted)
        try await writeBack.flush(using: writer)
        #expect(writer.completed.isEmpty)
    }

    @Test func routineItemsTickOnlyRepeatingReminders() async throws {
        try reconciler.apply(snap([routine("m", "Meds"), routine("w", "Water plants")]), now: at(7))
        writer.existing = ["m", "w"]
        writer.repeating = ["m"]
        try lifecycle.complete(try task("Meds"), now: at(8))
        try lifecycle.complete(try task("Water plants"), now: at(8))
        let result = try await writeBack.flush(using: writer)
        #expect(writer.completed == ["m"])          // the one-off stays open, or it'd leave the list
        #expect(result.written == 1 && result.dropped == 1)
    }

    @Test func aRepeatingRoutineReminderComingBackNewIsTheSameItem() throws {
        try reconciler.apply(snap([routine("m1")]), now: at(7))
        let meds = try task("Meds")
        // Ticked yesterday evening: the ticked reminder stays completed, the next date is a new one.
        let yesterday = day.adding(days: -1, calendar: calendar)
        try reconciler.apply(snap([routine("m1", done: at(21, on: yesterday)), routine("m2")]), now: at(8))
        let items = try Backlog(context: context).openTasks().filter(\.isRoutineItem)
        #expect(items.map(\.id) == [meds.id])
        #expect(try RoutineChecklist(context: context, calendar: calendar).isDone(meds, on: yesterday))
        // Later syncs keep it linked to the new reminder.
        try reconciler.apply(snap([routine("m1", done: at(21, on: yesterday)), routine("m2")]), now: at(9))
        #expect(try Backlog(context: context).openTasks().filter(\.isRoutineItem).count == 1)
        try reconciler.apply(snap([routine("m2")]), now: at(10))   // the old one ages out
        #expect(try Backlog(context: context).openTasks().filter(\.isRoutineItem).map(\.id) == [meds.id])
    }

    @Test func aSyncReplansOnlyDaysAlreadyPlanned() throws {
        let planning = DayPlanning(context: context, calendar: calendar)
        try reconciler.apply(snap([action()]), now: at(8))
        #expect(try planning.refreshPlannedDays(now: at(8)) == nil)   // nobody planned today
        #expect(try CalendarEngine(context: context).events(on: day, calendar: calendar).isEmpty)

        try planning.plan(day, now: at(8))
        try reconciler.apply(snap([action(), action("r2", "Book dentist")]), now: at(9))
        #expect(try planning.refreshPlannedDays(now: at(9)) == day)
        let dentist = try task("Book dentist")
        #expect(try !CalendarEngine(context: context).events(forTask: dentist.id).filter { $0.kind == .taskBlock }.isEmpty)
    }
}
