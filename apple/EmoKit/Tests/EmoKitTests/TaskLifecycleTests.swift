import Foundation
import SwiftData
import Testing
@testable import EmoKit

@MainActor
@Suite struct TaskLifecycleTests {
    let container = try! EmoStore.makeContainer(.inMemory)
    var context: ModelContext { container.mainContext }
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Rome")!
        return c
    }()
    let day = LocalDay(year: 2026, month: 11, day: 13)
    var tomorrow: LocalDay { day.adding(days: 1, calendar: calendar) }

    var lifecycle: TaskLifecycle { TaskLifecycle(context: context, calendar: calendar) }
    var planning: DayPlanning { DayPlanning(context: context, calendar: calendar) }
    var engine: CalendarEngine { CalendarEngine(context: context) }

    init() throws {
        try CheckIns(context: container.mainContext).record(mood: 3, energy: 5, for: day)
    }

    func at(_ hour: Int, _ minute: Int = 0, on d: LocalDay? = nil) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: (d ?? day).start(in: calendar))!
    }

    @discardableResult
    func addTask(_ name: String, hours: Double, cost: EnergyCost = .medium, created: Int = 0,
                 recurrence: Recurrence = .none, deadline: Date? = nil) throws -> TaskItem {
        try Backlog(context: context).add(
            TaskDraft(name: name, estimatedHours: hours, energyCost: cost, deadline: deadline, recurrence: recurrence),
            now: Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + created))
        )
    }

    func blocks(on d: LocalDay) throws -> [CalendarEvent] {
        try engine.events(on: d, calendar: calendar).filter { $0.kind == .taskBlock }
    }

    func titles(on d: LocalDay) throws -> [String] { try blocks(on: d).map(\.title) }

    // MARK: Complete

    @Test func completingRemovesFutureBlocksAndReplansTheFreedTime() throws {
        let a = try addTask("A", hours: 1, cost: .high, created: 0)
        try addTask("B", hours: 1, cost: .low, created: 1)
        try planning.plan(day, now: at(7))
        #expect(try titles(on: day) == ["A", "B"])   // A 9–10, B 10–11

        try lifecycle.complete(a, now: at(8))

        #expect(a.isCompleted)
        let after = try blocks(on: day)
        #expect(after.map(\.title) == ["B"])
        #expect(after.first?.start == at(9))   // B moved up into A's freed slot
    }

    @Test func completingMidBlockKeepsTheDonePartAsHistory() throws {
        let a = try addTask("A", hours: 2)
        try planning.plan(day, now: at(7))       // 9–11

        try lifecycle.complete(a, now: at(9, 40))

        let remaining = try blocks(on: day)
        #expect(remaining.count == 1)
        #expect(remaining.first?.start == at(9))
        #expect(remaining.first?.end == at(9, 40))
    }

    @Test func completingARecurringTaskCreatesTheNextOccurrence() throws {
        let gym = try addTask("Gym", hours: 1, recurrence: .daily, deadline: at(20))
        let next = try #require(try lifecycle.complete(gym, now: at(8)))

        #expect(next.name == "Gym")
        #expect(next.recurrence == .daily)
        #expect(next.deadline == at(20, on: tomorrow))
        #expect(!next.isCompleted)
        #expect(!next.isPlannable(on: day))
        #expect(next.isPlannable(on: tomorrow))

        let weekly = try addTask("Review", hours: 1, recurrence: .weekly)
        let nextWeekly = try #require(try lifecycle.complete(weekly, now: at(8)))
        #expect(nextWeekly.availableFromDayKey == day.adding(days: 7, calendar: calendar).key)
    }

    @Test func nextOccurrenceIsNotPlannedOnTheSameDay() throws {
        let gym = try addTask("Gym", hours: 1, recurrence: .daily)
        try planning.plan(day, now: at(7))
        try lifecycle.complete(gym, now: at(8))   // re-plans today (and tomorrow)

        #expect(try titles(on: day).isEmpty)
        #expect(try titles(on: tomorrow) == ["Gym"])
    }

    @Test func nonRecurringCompletionCreatesNothing() throws {
        let a = try addTask("Once", hours: 1)
        #expect(try lifecycle.complete(a, now: at(8)) == nil)
        #expect(try Backlog(context: context).openTasks().isEmpty)
    }

    // MARK: Skip

    @Test func skippingRemovesTheTaskFromTodayAndReplans() throws {
        let a = try addTask("A", hours: 1, cost: .high, created: 0)
        try addTask("B", hours: 1, cost: .low, created: 1)
        try planning.plan(day, now: at(7))

        try lifecycle.skip(a, on: day, now: at(8))

        #expect(try titles(on: day) == ["B"])
        #expect(try blocks(on: day).first?.start == at(9))
        #expect(try titles(on: tomorrow) == ["A"])      // back in play from tomorrow
        #expect(try Backlog(context: context).openTasks().contains { $0.id == a.id })

        try planning.plan(day, now: at(8))              // explicit re-plan still respects the skip
        #expect(try titles(on: day) == ["B"])
    }

    @Test func skippingAlsoRemovesAPinnedBlockThatDay() throws {
        let a = try addTask("A", hours: 1)
        try lifecycle.pin(a, start: at(15), end: at(16), now: at(8))
        try lifecycle.skip(a, on: day, now: at(8))
        #expect(try titles(on: day).isEmpty)
    }

    // MARK: Edit

    @Test func editingReplansDaysWhereTheTaskIsScheduled() throws {
        let a = try addTask("A", hours: 1)
        try planning.plan(day, now: at(7))

        var draft = TaskDraft(a)
        draft.name = "A, renamed"
        draft.estimatedHours = 2
        try lifecycle.update(a, with: draft, now: at(8))

        let after = try blocks(on: day)
        #expect(after.map(\.title) == ["A, renamed"])
        #expect(after.reduce(0) { $0 + $1.duration } == 2 * 3600)
    }

    @Test func editingAnUnscheduledTaskLeavesTheCalendarAlone() throws {
        let fixed = try engine.createFixedEvent(title: "Lunch", start: at(12), end: at(13))
        let a = try addTask("A", hours: 1)
        var draft = TaskDraft(a)
        draft.estimatedHours = 3
        try lifecycle.update(a, with: draft, now: at(8))

        #expect(try engine.events(on: day, calendar: calendar).map(\.id) == [fixed.id])
    }

    @Test func invalidEditIsRejected() throws {
        let a = try addTask("A", hours: 1)
        var draft = TaskDraft(a)
        draft.name = " "
        #expect(throws: TaskDraft.ValidationError.emptyName) { try lifecycle.update(a, with: draft) }
        #expect(a.name == "A")
    }

    // MARK: Delete

    @Test func deletingRemovesTaskAndBlocksAndReplans() throws {
        let a = try addTask("A", hours: 1, cost: .high, created: 0)
        try addTask("B", hours: 1, cost: .low, created: 1)
        try planning.plan(day, now: at(7))

        try lifecycle.delete(a, now: at(8))

        #expect(try Backlog(context: context).openTasks().map(\.name) == ["B"])
        #expect(try titles(on: day) == ["B"])
        #expect(try blocks(on: day).first?.start == at(9))
        #expect(try engine.events(forTask: a.id).isEmpty)
    }

    // MARK: Pin

    @Test func pinnedBlockSurvivesReplanningAndOthersFlowAroundIt() throws {
        let a = try addTask("A", hours: 1, cost: .high, created: 0)
        let b = try addTask("B", hours: 1, cost: .low, created: 1)
        try planning.plan(day, now: at(7))

        let pinned = try lifecycle.pin(b, start: at(9), end: at(10), now: at(8))
        try planning.plan(day, now: at(8))

        let after = try blocks(on: day)
        let kept = try #require(after.first { $0.id == pinned.id })
        #expect(kept.start == at(9) && kept.end == at(10) && kept.isLocked)
        #expect(after.filter { $0.taskID == b.id }.count == 1)           // not double-booked
        #expect(after.first { $0.taskID == a.id }?.start == at(10))      // flowed around the pin
    }

    @Test func pinningAShorterBlockLeavesTheRestPlannable() throws {
        let a = try addTask("A", hours: 2)
        try lifecycle.pin(a, start: at(15), end: at(16), now: at(8))
        let total = try blocks(on: day).filter { $0.taskID == a.id }.reduce(0) { $0 + $1.duration }
        #expect(total == 2 * 3600)
    }

    @Test func movingATaskBlockByHandPinsIt() throws {
        try addTask("A", hours: 1)
        try planning.plan(day, now: at(7))
        let block = try #require(try blocks(on: day).first)
        #expect(!block.isLocked)

        try engine.move(block, to: at(17))
        #expect(block.isLocked)
        try planning.plan(day, now: at(8))
        #expect(try blocks(on: day).map(\.start) == [at(17)])
    }

    @Test func deletingOneBlockReturnsItsTimeToTheBacklogWithoutReplanning() throws {
        let a = try addTask("A", hours: 1)
        try planning.plan(day, now: at(7))
        let block = try #require(try blocks(on: day).first)

        try engine.delete(block)

        #expect(try blocks(on: day).isEmpty)                       // not put straight back
        #expect(try Backlog(context: context).openTasks().map(\.id) == [a.id])
        try planning.plan(day, now: at(8))
        #expect(try titles(on: day) == ["A"])                      // next plan picks it up
    }
}
