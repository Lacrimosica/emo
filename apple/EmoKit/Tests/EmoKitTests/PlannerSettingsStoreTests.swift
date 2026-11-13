import Foundation
import SwiftData
import Testing
@testable import EmoKit

@MainActor
@Suite struct PlannerSettingsStoreTests {
    let container = try! EmoStore.makeContainer(.inMemory)
    var store: PlannerSettingsStore { PlannerSettingsStore(context: container.mainContext) }

    @Test func defaultsMatchLegacyBehaviour() {
        let s = store.load()
        #expect(s == .default)
        #expect(s.dayStartMinutes == 9 * 60 && s.dayEndMinutes == 22 * 60 && s.minimumChunkMinutes == 30)
        #expect(s.energyBudgetHours == [1: 2, 2: 3.5, 3: 5, 4: 6.5, 5: 8])
    }

    @Test func savedSettingsAreLoadedBackAndSavingAgainUpdates() throws {
        var s = PlannerSettings.default
        s.dayStartMinutes = 7 * 60 + 30
        s.minimumChunkMinutes = 45
        s.energyBudgetHours[3] = 4
        try store.save(s)
        #expect(store.load() == s)

        s.dayEndMinutes = 20 * 60
        try store.save(s)
        #expect(store.load() == s)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<PlannerPreferences>()) == 1)
    }

    @Test(arguments: [
        (PlannerSettings(dayStartMinutes: 600, dayEndMinutes: 600), PlannerSettingsStore.ValidationError.dayEndNotAfterStart),
        (PlannerSettings(dayStartMinutes: -1), .dayBoundsOutOfRange),
        (PlannerSettings(minimumChunkMinutes: 2), .minimumChunkOutOfRange),
        (PlannerSettings(energyBudgetHours: [1: 2, 2: 3, 3: 30, 4: 5, 5: 6]), .budgetOutOfRange),
        (PlannerSettings(energyBudgetHours: [1: 2]), .budgetOutOfRange),
        (PlannerSettings(defaultEnergy: 0), .defaultEnergyOutOfRange),
    ])
    func invalidSettingsAreRejected(settings: PlannerSettings, error: PlannerSettingsStore.ValidationError) throws {
        #expect(throws: error) { try store.save(settings) }
        #expect(store.load() == .default)
    }

    @Test func planningUsesSavedSettings() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Rome")!
        let day = LocalDay(year: 2026, month: 11, day: 13)
        let context = container.mainContext
        try CheckIns(context: context).record(mood: 3, energy: 5, for: day)
        try Backlog(context: context).add(TaskDraft(name: "Early bird", estimatedHours: 1))
        try store.save(PlannerSettings(dayStartMinutes: 6 * 60, dayEndMinutes: 12 * 60))

        try DayPlanning(context: context, calendar: calendar).plan(day, now: day.start(in: calendar))

        let block = try #require(try CalendarEngine(context: context).events(on: day, calendar: calendar).first)
        #expect(calendar.component(.hour, from: block.start) == 6)
    }
}
