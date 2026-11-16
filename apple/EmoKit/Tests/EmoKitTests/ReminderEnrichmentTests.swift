import Foundation
import SwiftData
import Testing
@testable import EmoKit

/// Returns one scripted enrichment reply and records the instructions it was given.
final class ScriptedEnrichmentProvider: LLMProvider, @unchecked Sendable {
    let id = "scripted"
    let displayName = "Scripted"
    var reply: EnrichmentReply
    private(set) var instructions: String?

    init(_ reply: EnrichmentReply) { self.reply = reply }

    func availability() async -> LLMAvailability { .available }

    func generate<Output: StructuredOutput>(_ type: Output.Type, instructions: String, conversation: [ChatTurn]) async throws -> Output {
        self.instructions = instructions
        return reply as! Output
    }
}

@MainActor
@Suite struct ReminderEnrichmentTests {
    let container = try! EmoStore.makeContainer(.inMemory)
    var context: ModelContext { container.mainContext }

    func reminderTask(_ name: String, area: String = "Personal", notes: String? = nil) throws -> TaskItem {
        let t = try Backlog(context: context).add(TaskDraft(name: name))
        t.listRole = .nextAction
        t.listArea = area
        t.notes = notes
        return t
    }

    let said = [ChatTurn(.user, "All the CV stuff is the job hunt, design roles in Milan. Send CV this week.")]

    @Test func proposesValidatedMinimalEditsPerReminder() async throws {
        let cv = try reminderTask("Send CV", notes: "Ask Marta first.")
        let update = try reminderTask("Update CV", notes: "part of: Job hunt")
        let provider = ScriptedEnrichmentProvider(EnrichmentReply(edits: [
            ProposedNotesEdit(reminder: "1", partOf: "Job hunt", context: "Design roles, Milan", when: "this week"),
            ProposedNotesEdit(reminder: "2", partOf: "Job hunt"),   // already says so: no change
        ]))
        let step = try await ReminderEnrichment(provider: provider).next(said, candidates: [cv, update])
        guard case .propose(let proposals, _) = step else { Issue.record("expected edits"); return }
        #expect(proposals.count == 1)
        let p = try #require(proposals.first)
        #expect(p.taskID == cv.id)
        #expect(p.changes == [.partOf: .some("Job hunt"), .context: .some("Design roles, Milan"), .when: .some("week")])
        #expect(p.after.freeText == "Ask Marta first.")
        #expect(cv.notes == "Ask Marta first.")   // nothing written before approval
    }

    @Test func instructionsCarryTheBasePromptRulesAndNumberedReminders() async throws {
        let cv = try reminderTask("Send CV", notes: "part of: Job hunt")
        let provider = ScriptedEnrichmentProvider(EnrichmentReply(question: "Which reminders?"))
        let step = try await ReminderEnrichment(provider: provider).next(said, candidates: [cv])
        #expect(step == .ask("Which reminders?"))
        let instructions = try #require(provider.instructions)
        #expect(instructions.hasPrefix(EmoPrompt.base))
        #expect(instructions.contains(ReminderEnrichment.rules))
        #expect(instructions.contains("[1] Send CV · next_action/Personal · part of: Job hunt"))
    }

    @Test func invalidValuesAreCleanedOrDropped() {
        let long = String(repeating: "design roles in Milan and Turin ", count: 5)
        let changes = ReminderEnrichment.validated(
            ProposedNotesEdit(reminder: "1", partOf: "#Job\nhunt", context: long, when: "someday"), title: "Send CV")
        #expect(changes[.partOf] == .some("Job hunt"))
        let context = try? #require(changes[.context] ?? nil)
        #expect((context?.count ?? 0) <= ReminderEnrichment.maxContextLength && context?.hasSuffix(" ") == false)
        #expect(changes[.when] == nil)   // not today/week: dropped
    }

    @Test func restatingTheTitleIsDroppedAndEmptyRemoves() {
        let changes = ReminderEnrichment.validated(
            ProposedNotesEdit(reminder: "1", partOf: "", context: "send cv", when: ""), title: "Send CV")
        #expect(changes[.context] == nil)
        #expect(changes[.partOf] == .some(nil) && changes[.when] == .some(nil))
    }

    @Test func theSchemaIsValidJSONAndCoversEveryKey() throws {
        let schema = try #require(try JSONSerialization.jsonObject(with: Data(EnrichmentReply.jsonSchema.utf8)) as? [String: Any])
        let items = ((schema["properties"] as? [String: Any])?["edits"] as? [String: Any])?["items"] as? [String: Any]
        let required = Set(items?["required"] as? [String] ?? [])
        #expect(required == ["reminder", "partOf", "context", "when", "ongoing"])
        #expect(Set(schema["required"] as? [String] ?? []) == ["question", "edits", "remember"])
    }

    @Test func ongoingEditsAlwaysCarryAnExplicitTarget() {
        #expect(ReminderEnrichment.validated(ProposedNotesEdit(reminder: "1", ongoing: "3 times a week"), title: "Study")[.ongoing] == .some("3x/week 1h"))
        #expect(ReminderEnrichment.validated(ProposedNotesEdit(reminder: "1", ongoing: "yes"), title: "Study")[.ongoing] == .some("2x/week 1h"))
        #expect(ReminderEnrichment.validated(ProposedNotesEdit(reminder: "1", ongoing: ""), title: "Study")[.ongoing] == .some(nil))
    }

    @Test func unknownIdsAreIgnored() throws {
        let cv = try reminderTask("Send CV")
        let proposals = ReminderEnrichment.proposals(from: [ProposedNotesEdit(reminder: "7", context: "x"),
                                                            ProposedNotesEdit(reminder: "[1]", context: "Milan")], candidates: [cv])
        #expect(proposals.map(\.taskID) == [cv.id])
    }

    @Test func relevantTasksMatchWhatTheUserSaid() throws {
        var tasks = try (0..<40).map { try reminderTask("Chore \($0)", area: "Home") }
        let cv = try reminderTask("Send CV", area: "Personal")
        tasks.append(cv)
        let picked = ReminderEnrichment.relevant(tasks, to: said, limit: 10)
        #expect(picked.first?.id == cv.id && picked.count == 1)
        let fallback = ReminderEnrichment.relevant(tasks, to: [ChatTurn(.user, "zzz")], limit: 10)
        #expect(fallback.count == 10)
    }

    @Test func onlyRemindersLinkedTasksAreCandidates() throws {
        let linked = try reminderTask("Send CV")
        try Backlog(context: context).add(TaskDraft(name: "Emo-only task"))
        let link = ExternalLink(provider: AppleRemindersSource.provider, externalID: "r1", sourceID: "home", contentHash: "", now: .now)
        link.taskID = linked.id
        context.insert(link)
        #expect(try ReminderEnrichment.linkedOpenTasks(context: context).map(\.id) == [linked.id])
    }
}

@MainActor
@Suite struct VagueTaskTests {
    let container = try! EmoStore.makeContainer(.inMemory)

    func task(_ name: String, role: ListRole?, notes: String? = nil) throws -> TaskItem {
        let t = try Backlog(context: container.mainContext).add(TaskDraft(name: name))
        t.listRole = role
        t.notes = notes
        return t
    }

    @Test func shortOrInboxImportsWithoutContextLookVague() throws {
        #expect(try task("DEB call", role: .nextAction).looksVague)
        #expect(try task("Look into the thing Sam mentioned", role: .inbox).looksVague)
        #expect(try !task("Book the dentist for the kids", role: .nextAction).looksVague)
        #expect(try !task("DEB call", role: .nextAction, notes: "context: weekly sync with the bank").looksVague)
        #expect(try !task("Gym", role: nil).looksVague)   // created in Emo: the user knows what it is
    }
}
