import Foundation
import SwiftData
import Testing
@testable import EmoKit

@MainActor
@Suite struct BacklogTests {
    @Test func addedTaskAppearsInBacklog() throws {
        let container = try EmoStore.makeContainer(.inMemory)
        let backlog = Backlog(context: container.mainContext)

        let deadline = Date(timeIntervalSince1970: 1_800_000_000)
        try backlog.add(TaskDraft(
            name: "  Write report  ",
            estimatedHours: 1.5,
            energyCost: .high,
            category: .externalCommitment,
            deadline: deadline
        ))

        let tasks = try backlog.openTasks()
        #expect(tasks.count == 1)
        let task = try #require(tasks.first)
        #expect(task.name == "Write report")
        #expect(task.estimatedHours == 1.5)
        #expect(task.energyCost == .high)
        #expect(task.category == .externalCommitment)
        #expect(task.deadline == deadline)
        #expect(task.recurrence == .none)
        #expect(!task.isCompleted)
    }

    @Test func backlogIsNewestFirstAndExcludesCompleted() throws {
        let container = try EmoStore.makeContainer(.inMemory)
        let backlog = Backlog(context: container.mainContext)
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)

        try backlog.add(TaskDraft(name: "Old"), now: t0)
        let done = try backlog.add(TaskDraft(name: "Done"), now: t0.addingTimeInterval(60))
        try backlog.add(TaskDraft(name: "New"), now: t0.addingTimeInterval(120))
        done.completedAt = t0.addingTimeInterval(180)
        try container.mainContext.save()

        #expect(try backlog.openTasks().map(\.name) == ["New", "Old"])
    }

    @Test func invalidDraftsAreRejectedAndNothingIsSaved() throws {
        let container = try EmoStore.makeContainer(.inMemory)
        let backlog = Backlog(context: container.mainContext)

        #expect(throws: TaskDraft.ValidationError.emptyName) {
            try backlog.add(TaskDraft(name: "   "))
        }
        #expect(throws: TaskDraft.ValidationError.nonPositiveEstimate) {
            try backlog.add(TaskDraft(name: "Thing", estimatedHours: 0))
        }
        #expect(try backlog.openTasks().isEmpty)
    }

    @Test func tasksSurviveReopeningTheStore() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("emo-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            let container = try EmoStore.makeContainer(.file(url))
            try Backlog(context: container.mainContext).add(TaskDraft(name: "Persist me"))
        }

        let reopened = try EmoStore.makeContainer(.file(url))
        #expect(try Backlog(context: reopened.mainContext).openTasks().map(\.name) == ["Persist me"])
    }
}
