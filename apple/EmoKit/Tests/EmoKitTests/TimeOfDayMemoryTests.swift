import Foundation
import SwiftData
import Testing
@testable import EmoKit

/// Ticket 20: time-of-day patterns.
@MainActor
@Suite struct TimeOfDayMemoryTests {
    let container = try! EmoStore.makeContainer(.inMemory)
    var context: ModelContext { container.mainContext }
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Rome")!
        return c
    }()
    let day = LocalDay(year: 2026, month: 11, day: 13)
    func at(_ hour: Int, _ minute: Int = 0, on d: LocalDay? = nil) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: (d ?? day).start(in: calendar))!
    }
    var memory: TimeOfDayMemory { TimeOfDayMemory(context: context, calendar: calendar) }

    func task(_ name: String, area: String? = nil, hours: Double = 1, cost: EnergyCost = .medium) throws -> TaskItem {
        let t = try Backlog(context: context).add(TaskDraft(name: name, estimatedHours: hours, energyCost: cost))
        t.listArea = area
        return t
    }

    @Test func learnsAWindowOnceThereIsEnoughSignal() throws {
        let errand = try task("Post office", area: "Errands")
        try memory.record(.completed, for: errand, at: at(15))
        #expect(try memory.preferredWindow(for: errand) == nil)   // one hint isn't a pattern
        try memory.record(.completed, for: errand, at: at(16, 30))
        try memory.record(.movedByHand, for: errand, at: at(17))
        let window = try #require(try memory.preferredWindow(for: errand))
        #expect(window.startMinutes <= 15 * 60 && window.endMinutes >= 18 * 60)
    }

    @Test func scatteredHintsLearnNothing() throws {
        let t = try task("Misc", area: "Home")
        for hour in [7, 11, 15, 19, 22] { try memory.record(.completed, for: t, at: at(hour)) }
        #expect(try memory.preferredWindow(for: t) == nil)
    }

    @Test func skipsCountAgainstATime() throws {
        let t = try task("Study", area: "Poli")
        for _ in 0..<3 { try memory.record(.completed, for: t, at: at(9)) }
        for _ in 0..<3 { try memory.record(.skipped, for: t, at: at(9)) }
        #expect(try memory.preferredWindow(for: t) == nil)
    }

    @Test func thePlannerUsesThePreferredWindowWhenFree() throws {
        let errand = try task("Post office", area: "Errands")
        for hour in [15, 16, 16] { try memory.record(.movedByHand, for: errand, at: at(hour)) }
        try DayPlanning(context: context, calendar: calendar).plan(day, now: at(8))
        let block = try #require(try CalendarEngine(context: context).events(forTask: errand.id).first { $0.kind == .taskBlock })
        let window = try #require(try memory.preferredWindow(for: errand))
        #expect(block.start >= window.interval(on: day, calendar: calendar).start)
        #expect(block.end <= window.interval(on: day, calendar: calendar).end)
    }

    @Test func aBusyWindowFallsBackToOtherTime() throws {
        let errand = try task("Post office", area: "Errands")
        for hour in [15, 16, 16] { try memory.record(.movedByHand, for: errand, at: at(hour)) }
        let window = try #require(try memory.preferredWindow(for: errand)).interval(on: day, calendar: calendar)
        try CalendarEngine(context: context).createFixedEvent(title: "Workshop", start: window.start, end: window.end)
        try DayPlanning(context: context, calendar: calendar).plan(day, now: at(8))
        #expect(try CalendarEngine(context: context).events(forTask: errand.id).contains { $0.kind == .taskBlock })
    }

    @Test func thePreferenceNeverOverridesPriority() {
        // Budget for one task: the high-energy one wins even though the other prefers this time.
        let urgent = PlannableTask(id: UUID(), remaining: 3600, energyCost: .high, deadline: nil, createdAt: .distantPast)
        let preferring = PlannableTask(id: UUID(), remaining: 3600, energyCost: .low, deadline: nil, createdAt: .distantPast,
                                       preferredWindow: PreferredWindow(startMinutes: 9 * 60, endMinutes: 13 * 60))
        var settings = PlannerSettings.default
        settings.energyBudgetHours[1] = 1
        let plan = DayPlanner.plan(.init(day: day, calendar: calendar, notBefore: at(8), busy: [],
                                         tasks: [preferring, urgent], energy: 1, settings: settings))
        #expect(plan.blocks.map(\.taskID) == [urgent.id])
    }

    @Test func movingABlockByHandAndSkippingAreRecorded() throws {
        let t = try task("Gym", area: "Health")
        try DayPlanning(context: context, calendar: calendar).plan(day, now: at(8))
        let block = try #require(try CalendarEngine(context: context).events(forTask: t.id).first { $0.kind == .taskBlock })
        try CalendarEngine(context: context).move(block, to: at(18))
        try TaskLifecycle(context: context, calendar: calendar).skip(t, on: day, now: at(8, 30))
        let weights = try context.fetch(FetchDescriptor<TimeOfDayObservation>()).map(\.weight).sorted()
        #expect(weights == [-1, 2])
    }

    @Test func resetForgetsEverything() throws {
        let t = try task("Gym", area: "Health")
        for _ in 0..<3 { try memory.record(.completed, for: t, at: at(18)) }
        try memory.reset()
        #expect(try memory.learned().isEmpty)
    }
}
