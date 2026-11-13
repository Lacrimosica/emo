import Foundation
import SwiftData
import Testing
@testable import EmoKit

/// Stands in for Reminders.app: holds reminders and merges notes like the real writer.
@MainActor
final class FakeRemindersWriter: ReminderNotesWriting {
    var reminders: [String: ExternalReminder] = [:]
    var failing = false
    private(set) var saves = 0

    func updateNotes(externalID: String, changes: [ReminderNotes.Key: String?]) async throws -> ExternalReminder? {
        if failing { throw LLMError.transport("Reminders is unavailable") }
        guard var reminder = reminders[externalID] else { return nil }
        let merged = ReminderNotes(reminder.notes).merging(changes)
        if merged != reminder.notes { reminder.notes = merged; saves += 1 }
        reminders[externalID] = reminder
        return reminder
    }
}

@MainActor
@Suite struct ReminderNotesWriteBackTests {
    let container = try! EmoStore.makeContainer(.inMemory)
    var context: ModelContext { container.mainContext }
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Rome")!
        return c
    }()
    let now = Date(timeIntervalSince1970: 1_794_560_400)   // 2026-11-13
    let writer = FakeRemindersWriter()

    var writeBack: ReminderNotesWriteBack { ReminderNotesWriteBack(context: context, calendar: calendar) }
    var reconciler: ReminderReconciler { ReminderReconciler(context: context, calendar: calendar) }

    func reminder(notes: String) -> ExternalReminder {
        ExternalReminder(externalID: "r1", sourceID: "home", title: "Send CV", list: .infer(fromTitle: "NA - Personal"), notes: notes)
    }

    /// Imports one reminder and mirrors it in the fake Reminders.app.
    func imported(notes: String) throws -> TaskItem {
        let r = reminder(notes: notes)
        writer.reminders["r1"] = r
        try reconciler.apply(ReminderSnapshot(provider: "apple-reminders", sources: ["home"], reminders: [r]), now: now)
        return try #require(try Backlog(context: context).openTasks().first)
    }

    func sync() throws -> ReminderReconciler.Result {
        try reconciler.apply(ReminderSnapshot(provider: "apple-reminders", sources: ["home"],
                                              reminders: Array(writer.reminders.values)), now: now)
    }

    @Test func writesOnlyKeyedLinesAndKeepsTheUsersText() async throws {
        let task = try imported(notes: "Ask Marta first.\n  - portfolio link  ")
        try writeBack.queue([.partOf: "Job hunt", .when: "week"], for: task, now: now)
        #expect(task.partOf == "Job hunt")   // applied locally at once

        let result = try await writeBack.flush(using: writer, now: now)
        #expect(result.written == 1)
        #expect(writer.reminders["r1"]?.notes == "part of: Job hunt\nwhen: week\nAsk Marta first.\n  - portfolio link  ")
        #expect(task.pendingNotesEditsJSON == nil)
    }

    @Test func emosOwnWriteIsNotReadBackAsAnUpstreamEdit() async throws {
        let task = try imported(notes: "")
        try writeBack.queue([.context: "Milan"], for: task, now: now)
        try await writeBack.flush(using: writer, now: now)
        #expect(!(try sync()).changed)
    }

    @Test func repeatedWritesAreIdempotent() async throws {
        let task = try imported(notes: "context: Milan")
        #expect(try writeBack.queue([.context: " Milan "], for: task, now: now).isEmpty)
        #expect(try writeBack.queue([.when: nil], for: task, now: now).isEmpty)   // nothing to remove
        try await writeBack.flush(using: writer, now: now)
        #expect(writer.saves == 0)
    }

    @Test func anEmptyValueRemovesJustThatLine() async throws {
        let task = try imported(notes: "when: today\nCall Sam\ncontext: x")
        try writeBack.queue([.when: ""], for: task, now: now)
        try await writeBack.flush(using: writer, now: now)
        #expect(writer.reminders["r1"]?.notes == "Call Sam\ncontext: x")
    }

    @Test func mergesOntoNotesChangedInRemindersSinceTheLastSync() async throws {
        let task = try imported(notes: "Call Sam")
        try writeBack.queue([.when: "today"], for: task, now: now)
        writer.reminders["r1"]?.notes = "Call Sam\nBring the contract"   // edited on the phone meanwhile
        try await writeBack.flush(using: writer, now: now)
        #expect(writer.reminders["r1"]?.notes == "when: today\nCall Sam\nBring the contract")
        #expect(task.notes == "when: today\nCall Sam\nBring the contract")
    }

    @Test func aFailedWriteStaysQueuedAndIsRetried() async throws {
        let task = try imported(notes: "")
        try writeBack.queue([.when: "today"], for: task, now: now)
        writer.failing = true
        let failed = try await writeBack.flush(using: writer, now: now)
        #expect(failed.failed == 1 && task.pendingNotesEditsJSON != nil)

        // A sync in between keeps the local edit applied.
        writer.reminders["r1"]?.title = "Send the CV"
        try sync()
        #expect(task.parsedNotes.when == .today)

        writer.failing = false
        let retried = try await writeBack.flush(using: writer, now: now)
        #expect(retried.written == 1 && writer.reminders["r1"]?.notes == "when: today")
    }

    @Test func editsForADeletedReminderAreDropped() async throws {
        let task = try imported(notes: "")
        try writeBack.queue([.when: "week"], for: task, now: now)
        writer.reminders["r1"] = nil
        let result = try await writeBack.flush(using: writer, now: now)
        #expect(result.dropped == 1 && task.pendingNotesEditsJSON == nil)
    }

    @Test func queuedGoalsTakeEffectAtOnce() throws {
        let task = try imported(notes: "")
        try writeBack.queue([.when: "today"], for: task, now: now)
        #expect(task.goal(on: LocalDay(now, calendar: calendar), calendar: calendar) == .today)
    }

    @Test func pendingEditsSurviveEncoding() {
        var changes = ReminderNotesWriteBack.Changes()
        changes.updateValue("today", forKey: .when)
        changes.updateValue(nil, forKey: .context)   // a removal
        #expect(ReminderNotesWriteBack.decode(ReminderNotesWriteBack.encode(changes)) == changes)
    }
}
