import Foundation
import SwiftData
import Testing
@testable import EmoKit

/// Ticket 18: sizing learned from the user's edits.
@MainActor
@Suite struct SchedulingMemoryTests {
    let container = try! EmoStore.makeContainer(.inMemory)
    var context: ModelContext { container.mainContext }
    var memory: SchedulingMemory { SchedulingMemory(context: context) }

    func sized(_ name: String, area: String? = nil, hours: Double, cost: EnergyCost = .medium,
               category: TaskCategory = .personal, at seconds: TimeInterval) throws {
        let task = try Backlog(context: context).add(TaskDraft(name: name, estimatedHours: hours, energyCost: cost, category: category))
        task.listArea = area
        try memory.record(task, now: Date(timeIntervalSince1970: seconds))
    }

    @Test func repeatedEditsConvergeOnTheUsersSizing() throws {
        try sized("Call the dentist", area: "Home", hours: 0.25, cost: .low, category: .selfCare, at: 1)
        try sized("Call the bank", area: "Home", hours: 0.5, cost: .low, at: 2)
        try sized("Call the dentist again", area: "Home", hours: 0.25, cost: .low, category: .selfCare, at: 3)
        let s = try #require(try memory.suggest(for: "Call dentist", area: "Home"))
        #expect(s.estimatedHours == 0.25 && s.energyCost == .low && s.category == .selfCare)
    }

    @Test func unrelatedTitlesDontMatch() throws {
        try sized("Call the dentist", area: "Home", hours: 0.25, at: 1)
        #expect(try memory.suggest(for: "Write thesis chapter", area: "Home") == nil)
        #expect(try memory.suggest(for: "Book dentist appointment for the kids and the car service", area: nil) == nil)
    }

    @Test func areaDisambiguates() throws {
        try sized("Admin forms", area: "Poli", hours: 2, cost: .high, at: 1)
        try sized("Admin forms", area: "Home", hours: 0.5, cost: .low, at: 2)
        #expect(try memory.suggest(for: "Admin forms", area: "Poli")?.estimatedHours == 2)
        #expect(try memory.suggest(for: "Admin forms", area: "Home")?.estimatedHours == 0.5)
    }

    @Test func recentSizingWeighsMore() throws {
        try sized("Weekly report", hours: 1, at: 1)
        try sized("Weekly report", hours: 3, at: 2)
        let estimate = try #require(try memory.suggest(for: "Weekly report", area: nil)).estimatedHours
        #expect(estimate > 2 && estimate < 3)
    }

    @Test func keywordsIgnoreFillerAndPlurals() {
        #expect(SchedulingMemory.keywords("Buy the groceries for Saturday") == ["buy", "grocerie", "saturday"])
        #expect(SchedulingMemory.keywords("Email emails") == ["email"])
    }

    @Test func importsUseLearnedSizingAndSayItCameFromMemory() throws {
        try sized("Call the dentist", area: "Home", hours: 0.25, cost: .low, category: .selfCare, at: 1)
        let reconciler = ReminderReconciler(context: context)
        let reminders = [
            ExternalReminder(externalID: "1", sourceID: "home", title: "Call dentist", list: .infer(fromTitle: "NA - Home")),
            ExternalReminder(externalID: "2", sourceID: "home", title: "Repaint the fence", list: .infer(fromTitle: "NA - Home")),
        ]
        try reconciler.apply(ReminderSnapshot(provider: "apple-reminders", sources: ["home"], reminders: reminders))
        let tasks = try Backlog(context: context).openTasks()
        let call = try #require(tasks.first { $0.name == "Call dentist" })
        let fence = try #require(tasks.first { $0.name == "Repaint the fence" })
        #expect(call.estimatedHours == 0.25 && call.sizedFromMemory && call.needsReview)
        #expect(fence.estimatedHours == ReminderReconciler.defaultEstimateHours && !fence.sizedFromMemory)
    }

    @Test func memoryIsBounded() throws {
        for i in 0..<(SchedulingMemory.capacity + 5) { try sized("Task \(i) thing", hours: 1, at: TimeInterval(i)) }
        #expect(try context.fetchCount(FetchDescriptor<SizingObservation>()) == SchedulingMemory.capacity)
    }
}
