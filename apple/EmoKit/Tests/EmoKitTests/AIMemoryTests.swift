import Foundation
import SwiftData
import Testing
@testable import EmoKit

/// Ticket 21: AI memory notes.
@MainActor
@Suite struct AIMemoryTests {
    let container = try! EmoStore.makeContainer(.inMemory)
    var memory: AIMemory { AIMemory(context: container.mainContext) }

    @Test func notesAreCleanedAndDeduplicated() throws {
        #expect(try memory.add("  Poli = university\n(Politecnico)  ")?.text == "Poli = university (Politecnico)")
        #expect(try memory.add("poli = UNIVERSITY (politecnico)") == nil)
        #expect(try memory.add("   ") == nil)
        #expect(try memory.add(String(repeating: "x", count: 300))?.text.count == AIMemory.maxLength)
    }

    @Test func withFewNotesAllAreRelevant() throws {
        try memory.add("Poli = university")
        try memory.add("Groceries happen Saturday morning")
        #expect(try memory.relevant(to: "dentist").count == 2)
    }

    @Test func withManyNotesOnlyMatchingOnesAreSent() throws {
        for i in 0..<10 { try memory.add("Unrelated fact number \(i)") }
        try memory.add("Groceries happen Saturday morning")
        #expect(try memory.relevant(to: "buy groceries") == ["Groceries happen Saturday morning"])
    }

    @Test func emptyingANoteDeletesIt() throws {
        let note = try #require(try memory.add("DEB tasks are usually calls"))
        try memory.update(note, text: " ")
        #expect(try memory.all().isEmpty)
    }

    @Test func theClarifierAndEnrichmentReadTheNotes() async throws {
        let notes = ["Poli = university"]
        let clarifier = ScriptedProvider([.success(ClarifierReply(question: "When?"))])
        _ = try await TaskClarifier(provider: clarifier).next([ChatTurn(.user, "poli forms")], memory: notes)
        #expect(clarifier.calls.first?.instructions.contains("- Poli = university") == true)
        #expect(ReminderEnrichment.instructions(for: [], memory: notes).contains("- Poli = university"))
        #expect(!ReminderEnrichment.instructions(for: []).contains("What you know about the user"))
    }

    @Test func enrichmentSuggestsANewFactToRemember() async throws {
        let provider = ScriptedEnrichmentProvider(EnrichmentReply(edits: [], remember: "DEB tasks are usually calls"))
        let step = try await ReminderEnrichment(provider: provider).next([ChatTurn(.user, "DEB stuff is always a call")], candidates: [])
        #expect(step == .propose([], remember: "DEB tasks are usually calls"))
        let known = try await ReminderEnrichment(provider: provider)
            .next([ChatTurn(.user, "DEB stuff is always a call")], candidates: [], memory: ["DEB tasks are usually calls"])
        #expect(known == .propose([], remember: nil))   // already known: not suggested again
    }
}
