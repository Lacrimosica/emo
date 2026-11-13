import Foundation
import Testing
@testable import EmoKit

@Suite struct DayPlannerTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()
    let day = LocalDay(year: 2026, month: 11, day: 13)

    func at(_ hour: Int, _ minute: Int = 0, on d: LocalDay? = nil) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: (d ?? day).start(in: calendar))!
    }

    func task(_ hours: Double, _ cost: EnergyCost = .medium, deadline: Date? = nil, created: Int = 0, id: UUID = UUID()) -> PlannableTask {
        PlannableTask(id: id, remaining: hours * 3600, energyCost: cost, deadline: deadline,
                      createdAt: Date(timeIntervalSince1970: TimeInterval(created)))
    }

    func input(
        tasks: [PlannableTask],
        busy: [DateInterval] = [],
        energy: Int? = 5,
        notBefore: Date? = nil,
        alreadyPlanned: TimeInterval = 0,
        settings: PlannerSettings = .default,
        on d: LocalDay? = nil
    ) -> DayPlanner.Input {
        let d = d ?? day
        return .init(day: d, calendar: calendar, notBefore: notBefore ?? d.start(in: calendar), busy: busy,
                     tasks: tasks, energy: energy, alreadyPlanned: alreadyPlanned, settings: settings)
    }

    func span(_ h1: Int, _ m1: Int, _ h2: Int, _ m2: Int) -> DateInterval {
        DateInterval(start: at(h1, m1), end: at(h2, m2))
    }

    @Test func placesTasksAroundFixedEventsFromDayStart() {
        let a = task(2, .high), b = task(1, .low)
        let plan = DayPlanner.plan(input(tasks: [b, a], busy: [span(10, 0, 11, 0)]))
        #expect(plan.blocks == [
            PlannedBlock(taskID: a.id, start: at(9), end: at(10)),
            PlannedBlock(taskID: a.id, start: at(11), end: at(12)),
            PlannedBlock(taskID: b.id, start: at(12), end: at(13)),
        ])
        #expect(plan.overflow.isEmpty)
    }

    @Test func energyBudgetCapsTheDay() {
        // Energy 1 → 2 hours of task work.
        let a = task(1.5, .high), b = task(1.5, .medium)
        let plan = DayPlanner.plan(input(tasks: [a, b], energy: 1))
        #expect(plan.plannedDuration == 2 * 3600)
        #expect(plan.blocks.last == PlannedBlock(taskID: b.id, start: at(10, 30), end: at(11)))
        #expect(plan.overflow.map(\.id) == [b.id])
        #expect(plan.overflow.first?.remaining == 3600)
    }

    @Test func budgetAccountsForWorkAlreadyKeptOnTheDay() {
        let plan = DayPlanner.plan(input(tasks: [task(3)], energy: 1, alreadyPlanned: 1.5 * 3600))
        #expect(plan.plannedDuration == 0.5 * 3600)
    }

    @Test func missingCheckInUsesDefaultEnergy() {
        let plan = DayPlanner.plan(input(tasks: [task(8)], energy: nil))
        #expect(plan.plannedDuration == 5 * 3600)   // default energy 3 → 5h
    }

    @Test func gapsShorterThanMinimumChunkAreSkipped() {
        let a = task(1)
        let plan = DayPlanner.plan(input(tasks: [a], busy: [span(9, 20, 12, 0)]))
        #expect(plan.blocks == [PlannedBlock(taskID: a.id, start: at(12), end: at(13))])
    }

    @Test func finalRemainderMayBeShorterThanMinimumChunk() {
        let a = task(1.25)   // 1h + 15m
        let plan = DayPlanner.plan(input(tasks: [a], busy: [span(10, 0, 11, 0)]))
        #expect(plan.blocks == [
            PlannedBlock(taskID: a.id, start: at(9), end: at(10)),
            PlannedBlock(taskID: a.id, start: at(11), end: at(11, 15)),
        ])
    }

    @Test func splitTaskFinishesWithAShortLastPiece() {
        // 40-minute gap, then free: 40m + the remaining 20m (allowed because it completes the task).
        let a = task(1)
        let plan = DayPlanner.plan(input(tasks: [a], busy: [span(9, 40, 11, 0)]))
        #expect(plan.blocks == [
            PlannedBlock(taskID: a.id, start: at(9), end: at(9, 40)),
            PlannedBlock(taskID: a.id, start: at(11), end: at(11, 20)),
        ])
    }

    @Test func shortTaskUsesAGapBelowMinimumChunk() {
        let long = task(1, .high), short = task(0.25, .low)
        let plan = DayPlanner.plan(input(tasks: [long, short], busy: [span(9, 20, 12, 0)]))
        #expect(plan.blocks == [
            PlannedBlock(taskID: short.id, start: at(9), end: at(9, 15)),
            PlannedBlock(taskID: long.id, start: at(12), end: at(13)),
        ])
    }

    @Test func urgentDeadlineBeatsEnergyCost() {
        let heavy = task(1, .high)
        let urgent = task(1, .low, deadline: at(18))
        let plan = DayPlanner.plan(input(tasks: [heavy, urgent], notBefore: at(8)))
        #expect(plan.blocks.first?.taskID == urgent.id)
    }

    @Test func olderTaskWinsTies() {
        let newer = task(1, created: 200), older = task(1, created: 100)
        let plan = DayPlanner.plan(input(tasks: [newer, older]))
        #expect(plan.blocks.map(\.taskID) == [older.id, newer.id])
    }

    @Test func planningTodaySkipsTimeThatHasPassed() {
        let a = task(1)
        let plan = DayPlanner.plan(input(tasks: [a], notBefore: at(14, 10)))
        #expect(plan.blocks == [PlannedBlock(taskID: a.id, start: at(14, 10), end: at(15, 10))])
    }

    @Test func planningFromNowStartsAtTheNextFiveMinuteMark() {
        let a = task(1)
        let plan = DayPlanner.plan(input(tasks: [a], notBefore: at(14, 52).addingTimeInterval(59)))
        #expect(plan.blocks.first?.start == at(14, 55))
        let exact = DayPlanner.plan(input(tasks: [a], notBefore: at(15, 0)))
        #expect(exact.blocks.first?.start == at(15, 0))
    }

    @Test func nothingIsPlacedAfterDayEnd() {
        let a = task(3)
        let plan = DayPlanner.plan(input(tasks: [a], notBefore: at(20)))
        #expect(plan.blocks.last?.end == at(22))
        #expect(plan.overflow.first?.remaining == 3600)
    }

    @Test func nothingFitsAfterDayEndHasPassed() {
        let plan = DayPlanner.plan(input(tasks: [task(1)], notBefore: at(23, 30)))
        #expect(plan.blocks.isEmpty)
        #expect(plan.overflow.count == 1)
    }

    @Test func dstDayUsesWallClockWindow() {
        // US DST ends 2026-11-01: 25-hour day. Window must still be 9:00–22:00 local.
        let dstDay = LocalDay(year: 2026, month: 11, day: 1)
        let a = task(1)
        let plan = DayPlanner.plan(input(tasks: [a], on: dstDay))
        #expect(plan.blocks == [PlannedBlock(taskID: a.id, start: at(9, on: dstDay), end: at(10, on: dstDay))])
    }

    @Test func customSettingsAreRespected() {
        let settings = PlannerSettings(dayStartMinutes: 7 * 60 + 30, dayEndMinutes: 8 * 60 + 30, minimumChunkMinutes: 15)
        let a = task(2)
        let plan = DayPlanner.plan(input(tasks: [a], settings: settings))
        #expect(plan.blocks == [PlannedBlock(taskID: a.id, start: at(7, 30), end: at(8, 30))])
        #expect(plan.overflow.first?.remaining == 3600)
    }

    @Test func overlappingBusyIntervalsAreMerged() {
        let a = task(1)
        let plan = DayPlanner.plan(input(tasks: [a], busy: [span(9, 0, 10, 30), span(10, 0, 11, 0)]))
        #expect(plan.blocks.first?.start == at(11))
    }
}
