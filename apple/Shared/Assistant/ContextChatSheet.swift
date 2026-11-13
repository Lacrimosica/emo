import EmoKit
import SwiftData
import SwiftUI

/// "Add Context": tell Emo about your reminders in your own words; it proposes small edits to their
/// keyed note lines (part of, context, when), you approve each reminder, and the approved ones are
/// written back to Reminders. Scoped to one task, it's "Clarify with Emo" for a vague reminder.
struct ContextChatSheet: View {
    /// Limits the chat to this one task; nil considers every open task from Reminders.
    var scope: TaskItem? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(RemindersSyncService.self) private var remindersSync

    @State private var conversation: [ChatTurn] = []
    @State private var input = ""
    @State private var isThinking = false
    @State private var proposals: [ReminderEnrichment.Proposal]?
    @State private var approved: Set<UUID> = []
    @State private var isWriting = false
    @State private var errorMessage: String?
    @State private var unavailableReason: String?
    @FocusState private var inputFocused: Bool

    private let provider = AIProviders.current()

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ChatBubble(role: .assistant, text: greeting)
                        ForEach(conversation) { turn in
                            ChatBubble(role: turn.role, text: turn.text).id(turn.id)
                        }
                        if isThinking {
                            ProgressView().controlSize(.small).padding(.leading, 8).id("thinking")
                        }
                        if let proposals {
                            review(proposals).id("review")
                        }
                        if let errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                                .font(.callout)
                        }
                    }
                    .padding(16)
                }
                .onChange(of: conversation.count) { scrollToEnd(proxy) }
                .onChange(of: proposals) { scrollToEnd(proxy) }
            }

            if let unavailableReason {
                Label(unavailableReason, systemImage: "sparkles")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.quaternary)
            }

            Divider()
            HStack {
                TextField(scope == nil ? "e.g. the CV stuff is the job hunt, design roles in Milan" : "What is it about?",
                          text: $input, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .focused($inputFocused)
                    .onSubmit(send)
                    .disabled(unavailableReason != nil)
                Button("Send", systemImage: "arrow.up.circle.fill", action: send)
                    .labelStyle(.iconOnly)
                    .font(.title2)
                    .buttonStyle(.plain)
                    .foregroundStyle(canSend ? Color.accentColor : .secondary)
                    .disabled(!canSend)
                    .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(12)
        }
        #if os(macOS)
        .frame(width: 500, height: 560)
        #endif
        .navigationTitle(scope == nil ? "Add Context" : "Clarify with Emo")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
        }
        .task {
            if case .unavailable(let why) = await provider.availability() { unavailableReason = why }
            inputFocused = true
        }
    }

    private var greeting: String {
        if let scope {
            return "What's “\(scope.name)” about? I'll add a short note to the reminder so I can plan it better."
        }
        return "Tell me about your reminders in your own words: what a group of them is part of, context I should know, or what's for today or this week. I'll suggest small note changes for you to approve."
    }

    // MARK: Review

    private func review(_ proposals: [ReminderEnrichment.Proposal]) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                if proposals.isEmpty {
                    Text("Nothing to change: your reminders already say that, or I couldn't tell which ones you meant.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(proposals) { proposal in
                        ProposalRow(proposal: proposal, isApproved: Binding(
                            get: { approved.contains(proposal.id) },
                            set: { if $0 { approved.insert(proposal.id) } else { approved.remove(proposal.id) } }
                        ))
                        if proposal.id != proposals.last?.id { Divider() }
                    }
                    if !remindersSync.isEnabled {
                        Text("Reminders isn't connected on this device. Changes are saved in Emo and written to Reminders once it is.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Button("Not quite…") {
                            self.proposals = nil
                            inputFocused = true
                        }
                        Spacer()
                        Button(writeLabel) { Task { await write(proposals) } }
                            .buttonStyle(.borderedProminent)
                            .disabled(approved.isEmpty || isWriting)
                    }
                }
            }
            .padding(4)
        } label: {
            Label(proposals.isEmpty ? "No changes" : "Suggested changes", systemImage: "sparkles")
        }
    }

    private var writeLabel: String {
        approved.count == 1 ? "Update 1 Reminder" : "Update \(approved.count) Reminders"
    }

    private func write(_ proposals: [ReminderEnrichment.Proposal]) async {
        isWriting = true
        defer { isWriting = false }
        let backlog = Backlog(context: modelContext)
        var count = 0
        for proposal in proposals where approved.contains(proposal.id) {
            guard let task = try? backlog.task(withID: proposal.taskID) else { continue }
            if await !remindersSync.writeNotes(proposal.changes, for: task).isEmpty { count += 1 }
        }
        if let error = remindersSync.errorMessage, count == 0 {
            errorMessage = error
            return
        }
        dismiss()
    }

    // MARK: Chat

    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isThinking && unavailableReason == nil
    }

    private func send() {
        guard canSend else { return }
        conversation.append(ChatTurn(.user, input.trimmingCharacters(in: .whitespacesAndNewlines)))
        input = ""
        proposals = nil
        errorMessage = nil
        isThinking = true
        let snapshot = conversation
        let candidates: [TaskItem]
        if let scope {
            candidates = [scope]
        } else {
            let all = (try? ReminderEnrichment.linkedOpenTasks(context: modelContext)) ?? []
            candidates = ReminderEnrichment.relevant(all, to: snapshot)
        }
        guard !candidates.isEmpty else {
            isThinking = false
            errorMessage = "There are no reminders from Apple Reminders in your backlog yet. Turn on Reminders in Settings first."
            return
        }
        Task {
            defer { isThinking = false }
            do {
                switch try await ReminderEnrichment(provider: provider).next(snapshot, candidates: candidates) {
                case .ask(let question):
                    conversation.append(ChatTurn(.assistant, question))
                case .propose(let found):
                    approved = Set(found.map(\.id))
                    proposals = found
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        withAnimation {
            if proposals != nil { proxy.scrollTo("review", anchor: .bottom) }
            else if let last = conversation.last { proxy.scrollTo(last.id, anchor: .bottom) }
        }
    }
}

/// One reminder's proposed change: before → after for each key, with an approve switch.
private struct ProposalRow: View {
    let proposal: ReminderEnrichment.Proposal
    @Binding var isApproved: Bool

    var body: some View {
        Toggle(isOn: $isApproved) {
            VStack(alignment: .leading, spacing: 4) {
                Text(proposal.title).font(.headline)
                ForEach(ReminderNotes.Key.allCases.filter { proposal.changes.keys.contains($0) }, id: \.self) { key in
                    change(key)
                }
            }
        }
        #if os(macOS)
        .toggleStyle(.checkbox)
        #endif
        .accessibilityHint("Include this reminder when updating")
    }

    private func change(_ key: ReminderNotes.Key) -> some View {
        let before = proposal.before.fields[key].flatMap { $0.isEmpty ? nil : $0 }
        let after = proposal.after.fields[key].flatMap { $0.isEmpty ? nil : $0 }
        return HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("\(key.rawValue):").foregroundStyle(.secondary)
            if let before {
                Text(before).strikethrough().foregroundStyle(.secondary)
                if after != nil { Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary) }
            }
            if let after { Text(after) } else { Text("removed").italic().foregroundStyle(.secondary) }
        }
        .font(.callout)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(key.rawValue): \(before.map { "from \($0) " } ?? "")\(after.map { "to \($0)" } ?? "removed")")
    }
}
