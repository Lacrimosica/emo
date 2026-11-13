import Foundation
import SwiftData
import Testing
@testable import EmoKit

@MainActor
@Suite struct CalendarWriteBackTests {
    let container = try! EmoStore.makeContainer(.inMemory)
    var context: ModelContext { container.mainContext }
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Rome")!
        return c
    }()
    let day = LocalDay(year: 2026, month: 11, day: 13)
    var writeBack: CalendarWriteBack { CalendarWriteBack(context: context, calendar: calendar) }
    var window: DateInterval { DateInterval(start: day.start(in: calendar), end: day.adding(days: 14, calendar: calendar).start(in: calendar)) }
    func at(_ h: Int) -> Date { calendar.date(bySettingHour: h, minute: 0, second: 0, of: day.start(in: calendar))! }

    /// Applies operations like an adapter would, handing out fake external IDs.
    @discardableResult
    func sync() throws -> [CalendarWriteBack.Operation] {
        let ops = try writeBack.operations(desired: try writeBack.desiredEvents(from: day), window: window)
        for (i, op) in ops.enumerated() {
            if case .create = op { try writeBack.record(op, externalID: "ext-\(UUID().uuidString.prefix(4))-\(i)") }
            else { try writeBack.record(op, externalID: nil) }
        }
        return ops
    }

    func plan() throws {
        try CheckIns(context: context).record(mood: 3, energy: 5, for: day)
        try DayPlanning(context: context, calendar: calendar).plan(day, now: at(7))
    }

    @Test func plannedBlocksAreCreatedOnceAndFixedEventsAreNotMirrored() throws {
        try CalendarEngine(context: context).createFixedEvent(title: "Lunch", start: at(12), end: at(13))
        try Backlog(context: context).add(TaskDraft(name: "Essay", estimatedHours: 1, requiresTransit: true, transitMinutes: 15))
        try plan()

        let first = try sync()
        #expect(first.count == 2)   // transit + task block, not the fixed lunch
        #expect(first.allSatisfy { if case .create = $0 { true } else { false } })
        #expect(try sync().isEmpty)  // nothing changed → nothing to do
    }

    @Test func replanningUpdatesOrReplacesMirroredBlocks() throws {
        try Backlog(context: context).add(TaskDraft(name: "Essay", estimatedHours: 1))
        try plan()
        try sync()

        let block = try #require(try CalendarEngine(context: context).events(on: day, calendar: calendar).first)
        try CalendarEngine(context: context).move(block, to: at(15))
        let ops = try sync()
        #expect(ops.count == 1)
        guard case .update(_, let event) = ops[0] else { Issue.record("expected update"); return }
        #expect(event.start == at(15))
    }

    @Test func completedTasksAreRetracted() throws {
        let task = try Backlog(context: context).add(TaskDraft(name: "Essay", estimatedHours: 1))
        try plan()
        try sync()
        try TaskLifecycle(context: context, calendar: calendar).complete(task, now: at(8))
        let ops = try sync()
        #expect(ops.count == 1)
        guard case .delete = ops[0] else { Issue.record("expected delete"); return }
        #expect(try writeBack.writtenExternalIDs().isEmpty)
    }

    @Test func pastMirroredBlocksAreKeptAsHistory() throws {
        try Backlog(context: context).add(TaskDraft(name: "Essay", estimatedHours: 1))
        try plan()
        try sync()
        let tomorrowWindow = DateInterval(start: day.adding(days: 1, calendar: calendar).start(in: calendar), duration: 14 * 86_400)
        let ops = try writeBack.operations(desired: [], window: tomorrowWindow)
        #expect(ops.isEmpty)
    }

    @Test func forgetAllClearsTheRecord() throws {
        try Backlog(context: context).add(TaskDraft(name: "Essay", estimatedHours: 1))
        try plan()
        try sync()
        try writeBack.forgetAll()
        #expect(try writeBack.writtenExternalIDs().isEmpty)
    }
}
