import Foundation
import Testing
@testable import EmoKit

/// A provider that returns scripted replies and records what it was asked.
final class ScriptedProvider: LLMProvider, @unchecked Sendable {
    let id = "scripted"
    let displayName = "Scripted"
    var replies: [Result<ClarifierReply, Error>]
    private(set) var calls: [(instructions: String, conversation: [ChatTurn])] = []

    init(_ replies: [Result<ClarifierReply, Error>]) { self.replies = replies }

    func availability() async -> LLMAvailability { .available }

    func generate<Output: StructuredOutput>(_ type: Output.Type, instructions: String, conversation: [ChatTurn]) async throws -> Output {
        calls.append((instructions, conversation))
        let next = replies.removeFirst()
        return try next.get() as! Output
    }
}

@Suite struct TaskClarifierTests {
    let task = ProposedTask(name: "Write report", estimatedHours: 2, energyCost: "high", category: "external_commitment")

    @Test func asksAQuestionWhenTheModelNeedsOne() async throws {
        let provider = ScriptedProvider([.success(ClarifierReply(question: "How long will it take?"))])
        let step = try await TaskClarifier(provider: provider).next([ChatTurn(.user, "report")])
        #expect(step == .ask("How long will it take?"))
        #expect(provider.calls.first?.instructions == TaskClarifier.instructions)
    }

    @Test func proposalBecomesADraft() async throws {
        let provider = ScriptedProvider([.success(ClarifierReply(task: task))])
        let step = try await TaskClarifier(provider: provider).next([ChatTurn(.user, "2h report for my boss")])
        #expect(step == .propose(TaskDraft(name: "Write report", estimatedHours: 2, energyCost: .high, category: .externalCommitment)))
    }

    @Test func proposalWinsIfTheModelSendsBoth() async throws {
        let provider = ScriptedProvider([.success(ClarifierReply(question: "Anything else?", task: task))])
        guard case .propose = try await TaskClarifier(provider: provider).next([ChatTurn(.user, "x")]) else {
            Issue.record("expected a proposal"); return
        }
    }

    @Test func onlyTheFirstOfSeveralQuestionsIsAsked() async throws {
        let provider = ScriptedProvider([.success(ClarifierReply(question: "When is it due? And how long will it take?"))])
        let step = try await TaskClarifier(provider: provider).next([ChatTurn(.user, "x")])
        #expect(step == .ask("When is it due?"))
    }

    @Test func afterMaxQuestionsTheModelIsToldToProposeAndQuestionsAreRefused() async throws {
        var conversation: [ChatTurn] = [ChatTurn(.user, "something")]
        for i in 0..<TaskClarifier.maxQuestions {
            conversation += [ChatTurn(.assistant, "Q\(i)?"), ChatTurn(.user, "A\(i)")]
        }
        let provider = ScriptedProvider([.success(ClarifierReply(question: "One more?"))])
        await #expect(throws: LLMError.self) { try await TaskClarifier(provider: provider).next(conversation) }
        #expect(provider.calls.first?.instructions.contains("Reply with the task now") == true)
    }

    @Test func proposalsAreNormalised() {
        let odd = ProposedTask(name: "  Nap ", estimatedHours: 0.1, energyCost: "LOW", category: "nonsense")
        #expect(TaskClarifier.draft(from: odd) == TaskDraft(name: "Nap", estimatedHours: 0.25, energyCost: .low, category: .personal))
        let long = ProposedTask(name: "Move house", estimatedHours: 40, energyCost: "high", category: "personal")
        #expect(TaskClarifier.draft(from: long)?.estimatedHours == 24)
        #expect(TaskClarifier.draft(from: ProposedTask(name: " ", estimatedHours: 1, energyCost: "low", category: "leisure")) == nil)
    }

    @Test func emptyReplyIsAnError() async {
        let provider = ScriptedProvider([.success(ClarifierReply())])
        await #expect(throws: LLMError.self) { try await TaskClarifier(provider: provider).next([ChatTurn(.user, "x")]) }
    }

    @Test func providerErrorsPassThrough() async {
        let provider = ScriptedProvider([.failure(LLMError.unavailable("off"))])
        await #expect(throws: LLMError.unavailable("off")) { try await TaskClarifier(provider: provider).next([ChatTurn(.user, "x")]) }
    }

    @Test func transcriptFormatsRoles() {
        let text = ScriptedProvider.transcript([ChatTurn(.user, "hi"), ChatTurn(.assistant, "hello")])
        #expect(text == "User: hi\nAssistant: hello")
    }
}
