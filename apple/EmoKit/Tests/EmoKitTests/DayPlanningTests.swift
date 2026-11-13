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
                                            with: [(task, at(9, on: yesterday), at(10, on: yesterday))],
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

    @Test func planningAfterDayEndPushesEverythingToTomorrow() throws {
        try addTask("Late", hours: 1)
        let summary = try planning.plan(day, now: at(23))
        #expect(summary.planned.planned == 0)
        #expect(summary.spill.planned == 3600)
    }
}
