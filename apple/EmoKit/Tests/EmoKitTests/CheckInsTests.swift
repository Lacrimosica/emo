import Foundation
import SwiftData
import Testing
@testable import EmoKit

@MainActor
@Suite struct CheckInsTests {
    let container = try! EmoStore.makeContainer(.inMemory)
    var checkIns: CheckIns { CheckIns(context: container.mainContext) }
    let today = LocalDay(year: 2026, month: 11, day: 13)

    @Test func noCheckInUntilRecorded() throws {
        #expect(try checkIns.checkIn(for: today) == nil)
    }

    @Test func recordedCheckInIsReadBack() throws {
        try checkIns.record(mood: 4, energy: 2, for: today)
        let checkIn = try #require(try checkIns.checkIn(for: today))
        #expect(checkIn.mood == 4)
        #expect(checkIn.energy == 2)
        #expect(checkIn.day == today)
    }

    @Test func recordingAgainUpdatesInsteadOfDuplicating() throws {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        try checkIns.record(mood: 2, energy: 2, for: today, now: t0)
        try checkIns.record(mood: 5, energy: 3, for: today, now: t0.addingTimeInterval(60))

        let all = try container.mainContext.fetch(FetchDescriptor<CheckIn>())
        #expect(all.count == 1)
        #expect(all.first?.mood == 5)
        #expect(all.first?.energy == 3)
        #expect(all.first?.createdAt == t0)
    }

    @Test func checkInsAreScopedToTheirDay() throws {
        try checkIns.record(mood: 1, energy: 1, for: today.adding(days: -1))
        #expect(try checkIns.checkIn(for: today) == nil)
    }

    @Test func duplicatesFromSyncAreCollapsedOnNextRecord() throws {
        let context = container.mainContext
        context.insert(CheckIn(day: today, mood: 1, energy: 1))
        context.insert(CheckIn(day: today, mood: 2, energy: 2))
        try context.save()

        try checkIns.record(mood: 3, energy: 4, for: today)
        let all = try context.fetch(FetchDescriptor<CheckIn>())
        #expect(all.count == 1)
        #expect(all.first?.energy == 4)
    }

    @Test(arguments: [(0, 3), (6, 3), (3, 0), (3, 6)])
    func valuesOutsideOneToFiveAreRejected(mood: Int, energy: Int) throws {
        #expect(throws: CheckIns.ValidationError.self) {
            try checkIns.record(mood: mood, energy: energy, for: today)
        }
        #expect(try checkIns.checkIn(for: today) == nil)
    }
}
