import Foundation
import SwiftData
import Testing
@testable import EmoKit

/// Opens a store written by the build before categories and priorities existed (see
/// Fixtures/store-before-categories.store) and checks that the new schema reads it correctly.
@MainActor
@Suite struct StoreMigrationTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Rome")!
        return c
    }()
    let day = LocalDay(year: 2026, month: 11, day: 20)

    /// A throwaway copy of the fixture, so the test never writes to the checked-in file.
    func openedCopy() throws -> ModelContainer {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/store-before-categories.store")
        let copy = FileManager.default.temporaryDirectory
            .appendingPathComponent("emo-migration-\(UUID().uuidString).store")
        try FileManager.default.copyItem(at: fixture, to: copy)
        return try EmoStore.makeContainer(.file(copy))
    }

    @Test func oldTasksSurviveTheUpgrade() throws {
        let container = try openedCopy()
        let backlog = Backlog(context: container.mainContext)

        let all = try container.mainContext.fetch(FetchDescriptor<TaskItem>())
        #expect(all.count == 5)
        #expect(try backlog.openTasks().count == 4)
        #expect(all.filter(\.isCompleted).map(\.name) == ["Call dentist"])

        let report = try #require(all.first { $0.name == "Write report" })
        #expect(report.category == .externalCommitment)
        #expect(report.energyCost == .high)
        #expect(report.estimatedHours == 2)
        #expect(report.priority == .normal)          // new field: defaulted
        #expect(report.skippedDays.isEmpty)         // new field: defaulted

        let piano = try #require(all.first { $0.name == "Piano" })
        #expect(piano.isOngoing && piano.sessionsPerWeek == 3)
    }

    @Test func oldCalendarAndCheckInsSurviveTheUpgrade() throws {
        let container = try openedCopy()
        let context = container.mainContext
        let events = try context.fetch(FetchDescriptor<CalendarEvent>())
        #expect(events.filter { $0.kind == .taskBlock }.count == 5)
        #expect(events.contains { $0.title == "Dentist visit" && $0.kind == .fixed })
        #expect(try CheckIns(context: context).checkIn(for: day)?.energy == 4)
    }

    @Test func theCategoryListSeedsAroundOldKeys() throws {
        let container = try openedCopy()
        let catalog = CategoryCatalog(context: container.mainContext)
        try catalog.seedBuiltInsIfNeeded()
        let categories = try catalog.all()
        #expect(categories.map(\.key) == TaskCategory.builtIns.map(\.key))
        // The old tasks' categories resolve to the seeded built-ins, not to Personal.
        let report = try #require(try Backlog(context: container.mainContext).openTasks().first { $0.name == "Write report" })
        #expect(CategoryCatalog.name(for: report.categoryRaw, in: categories) == "External commitment")
    }

    @Test func planningWorksOnTheUpgradedStore() throws {
        let container = try openedCopy()
        let context = container.mainContext
        try CategoryCatalog(context: context).seedBuiltInsIfNeeded()
        let now = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: day.start(in: calendar))!
        let summary = try DayPlanning(context: context, calendar: calendar).plan(day, now: now)
        #expect(summary.planned.taskCount > 0)
        #expect(summary.planned.planned > 0)
    }
}
