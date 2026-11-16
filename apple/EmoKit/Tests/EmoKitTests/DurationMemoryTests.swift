import Foundation
import SwiftData
import Testing
@testable import EmoKit

/// Ticket 19: estimate vs. actual.
@MainActor
@Suite struct DurationMemoryTests {
    let container = try! EmoStore.makeContainer(.inMemory)
    var context: ModelContext { container.mainContext }
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Rome")!
        return c
    }()
    let day = LocalDay(year: 2026, month: 11, day: 16)
    func at(_ hour: Int, _ minute: Int = 0, on d: LocalDay? = nil) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: (d ?? day).start(in: calendar))!
    }
    var memory: DurationMemory { DurationMemory(context: context) }

    func task(_ name: String, area: String? = "Poli", hours: Double = 2) throws -> TaskItem {
        let t = try Backlog(context: context).add(TaskDraft(name: name, estimatedHours: hours))
        t.listArea = area
        return t
    }

    @Test func needsAFewCompletionsBeforeLearning() throws {
        let t = try task("Forms")
        try memory.record(t, actualHours: 1, now: at(10))
        try memory.record(t, actualHours: 1, now: at(11))
        #expect(try memory.learned(now: at(12)).isEmpty)
        try memory.record(t, actualHours: 1.4, now: at(12))
        let learned = try #require(try memory.learned(now: at(12)).first)
        #expect(learned.group == "area:poli")
        #expect(learned.factor == 0.55)   // 3.4h of 6h
        #expect(learned.observations == 3)
    }

    @Test func factorsAreBoundedAndIgnoreSmallDifferences() throws {
        let close = try task("Read", area: "Home")
        for _ in 0..<3 { try memory.record(close, actualHours: 2.1, now: at(10)) }
        #expect(try memory.factors(now: at(10))["area:home"] == nil)   // 1.05×: not worth correcting

        let long = try task("Thesis", area: "Uni", hours: 1)
        for _ in 0..<3 { try memory.record(long, actualHours: 2.9, now: at(10)) }
        #expect(try memory.factors(now: at(10))["area:uni"] == DurationMemory.factorRange.upperBound)
    }

    @Test func implausibleAndEmptyCompletionsAreIgnored() throws {
        let t = try task("Forms")
        try memory.record(t, actualHours: 0, now: at(10))      // nothing ran
        try memory.record(t, actualHours: 0.1, now: at(10))    // 0.05×: ticked by mistake
        try memory.record(t, actualHours: 10, now: at(10))     // 5×: forgot to tick
        #expect(try memory.count() == 0)
    }

    @Test func olderCompletionsCountLess() throws {
        let t = try task("Forms", hours: 1)
        let old = at(10, on: LocalDay(year: 2026, month: 5, day: 1))
        for _ in 0..<3 { try memory.record(t, actualHours: 2, now: old) }
        for _ in 0..<3 { try memory.record(t, actualHours: 0.5, now: at(10)) }
        let factor = try #require(try memory.factors(now: at(10))["area:poli"])
        #expect(factor < 0.6)   // the recent "half the estimate" dominates
    }

    @Test func completingATaskRecordsTheBlockTimeThatRan() throws {
        let t = try task("Forms", hours: 2)
        try CalendarEngine(context: context).pinTaskBlock(t, start: at(9), end: at(11), now: at(8))
        try TaskLifecycle(context: context, calendar: calendar).complete(t, now: at(10))
        let observation = try #require(try context.fetch(FetchDescriptor<DurationObservation>()).first)
        #expect(observation.estimatedHours == 2)
        #expect(observation.actualHours == 1)
    }

    @Test func syncedCompletionsAreNotLearnedFrom() throws {
        let t = try task("Forms", hours: 2)
        try CalendarEngine(context: context).pinTaskBlock(t, start: at(9), end: at(11), now: at(8))
        try TaskLifecycle(context: context, calendar: calendar).complete(t, now: at(10), learnTiming: false)
        #expect(try memory.count() == 0)
    }

    @Test func thePlannerReservesTheCorrectedTimeAndKeepsTheEstimate() throws {
        let done = try task("Old forms", hours: 2)
        for _ in 0..<3 { try memory.record(done, actualHours: 1, now: at(7)) }   // Poli: 0.5×
        let t = try task("New forms", hours: 2)
        try DayPlanning(context: context, calendar: calendar).plan(day, now: at(8))
        let planned = try CalendarEngine(context: context).events(forTask: t.id)
            .filter { $0.kind == .taskBlock }
            .reduce(0) { $0 + $1.duration }
        #expect(planned == 3600)
        #expect(t.estimatedHours == 2)
    }

    @Test func correctedTimeRoundsToFiveMinutes() {
        #expect(DurationMemory.corrected(1, by: nil) == 3600)
        #expect(DurationMemory.corrected(1, by: 0.55) == 35 * 60)   // 33 min, to the nearest 5
        #expect(DurationMemory.corrected(0.05, by: 0.5) == 5 * 60)  // never below 5 minutes
    }
}
