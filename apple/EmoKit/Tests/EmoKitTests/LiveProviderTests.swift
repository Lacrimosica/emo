import Foundation
import Testing
@testable import EmoKit

/// Hits real models. Opt in with EMO_LIVE_AI=1 (skipped in normal runs).
@Suite(.enabled(if: ProcessInfo.processInfo.environment["EMO_LIVE_AI"] == "1"))
struct LiveProviderTests {
    @Test func appleOnDeviceClarifiesATask() async throws {
        let provider = AppleOnDeviceProvider()
        let availability = await provider.availability()
        try #require(availability == .available, "on-device model unavailable: \(availability)")

        let step = try await TaskClarifier(provider: provider).next([
            ChatTurn(.user, "I need to write the quarterly report for my manager, it's a big one, probably 3 hours of focused work"),
        ])
        print("Apple on-device step:", step)
        if case .propose(let draft) = step {
            #expect(draft.isValid)
        }
    }

    @MainActor @Test func appleOnDeviceProposesReminderContext() async throws {
        let provider = AppleOnDeviceProvider()
        try #require(await provider.availability() == .available)
        let container = try EmoStore.makeContainer(.inMemory)
        let backlog = Backlog(context: container.mainContext)
        let tasks = try ["Send CV to studios", "Update portfolio site", "Buy dog food"].map { name in
            let t = try backlog.add(TaskDraft(name: name))
            t.listRole = .nextAction
            t.listArea = "Personal"
            return t
        }
        let step = try await ReminderEnrichment(provider: provider).next([
            ChatTurn(.user, "Sending the CV and the portfolio are part of the job hunt, for product design roles in Milan. The CV should go out this week."),
        ], candidates: tasks)
        print("Apple on-device enrichment:", step)
        if case .propose(let proposals) = step {
            #expect(!proposals.contains { $0.taskID == tasks[2].id }, "dog food shouldn't be touched")
        }
    }

    @Test func localOllamaClarifiesATask() async throws {
        let model = ProcessInfo.processInfo.environment["EMO_OLLAMA_MODEL"] ?? OllamaProvider.defaultModel
        let provider = OllamaProvider(model: model)
        let clarifier = TaskClarifier(provider: provider)

        let vague = try await clarifier.next([ChatTurn(.user, "dentist")])
        print("Ollama (\(model)) step for a vague request:", vague)

        let clear = try await clarifier.next([
            ChatTurn(.user, "I need to write the quarterly report for my manager, it's a big one, probably 3 hours of focused work"),
        ])
        print("Ollama (\(model)) step for a clear request:", clear)
        if case .propose(let draft) = clear {
            #expect(draft.isValid)
        }
    }
}
