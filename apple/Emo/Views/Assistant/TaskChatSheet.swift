import EmoKit
import SwiftData
import SwiftUI

/// "Ask Emo": describe a task loosely; the assistant asks at most one question at a time, then
/// proposes a task that the user reviews (and can adjust) before it's added.
struct TaskChatSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var conversation: [ChatTurn] = []
    @State private var input = ""
    @State private var isThinking = false
    @State private var proposal: TaskDraft?
    @State private var reviewing: TaskDraft?
    @State private var errorMessage: String?
    @State private var unavailableReason: String?
    @FocusState private var inputFocused: Bool

    private let provider = AIProviders.current()

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Bubble(role: .assistant, text: "What do you need to do? Describe it however you like.")
                        ForEach(conversation) { turn in
                            Bubble(role: turn.role, text: turn.text).id(turn.id)
                        }
                        if isThinking {
                            ProgressView().controlSize(.small).padding(.leading, 8).id("thinking")
                        }
                        if let proposal {
                            ProposalCard(draft: proposal, onAdd: { reviewing = proposal }, onKeepTalking: {
                                self.proposal = nil
                                inputFocused = true
                            })
                            .id("proposal")
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
                .onChange(of: proposal) { scrollToEnd(proxy) }
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
                TextField("Message", text: $input, axis: .vertical)
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
        .frame(width: 460, height: 520)
        .navigationTitle("Ask Emo")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
        }
        .sheet(item: $reviewing) { draft in
            TaskEditorSheet(task: nil, initialDraft: draft, onSaved: { dismiss() })
        }
        .task {
            if case .unavailable(let why) = await provider.availability() { unavailableReason = why }
            inputFocused = true
        }
    }

    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isThinking && unavailableReason == nil
    }

    private func send() {
        guard canSend else { return }
        conversation.append(ChatTurn(.user, input.trimmingCharacters(in: .whitespacesAndNewlines)))
        input = ""
        proposal = nil
        errorMessage = nil
        isThinking = true
        let snapshot = conversation
        Task {
            defer { isThinking = false }
            do {
                switch try await TaskClarifier(provider: provider).next(snapshot) {
                case .ask(let question): conversation.append(ChatTurn(.assistant, question))
                case .propose(let draft): proposal = draft
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        withAnimation {
            if proposal != nil { proxy.scrollTo("proposal", anchor: .bottom) }
            else if let last = conversation.last { proxy.scrollTo(last.id, anchor: .bottom) }
        }
    }
}

private struct Bubble: View {
    let role: ChatTurn.Role
    let text: String

    var body: some View {
        HStack {
            if role == .user { Spacer(minLength: 40) }
            Text(text)
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(role == .user ? Color.accentColor : Color.secondary.opacity(0.15),
                            in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(role == .user ? Color.white : Color.primary)
            if role == .assistant { Spacer(minLength: 40) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(role == .user ? "You" : "Emo"): \(text)")
    }
}

private struct ProposalCard: View {
    let draft: TaskDraft
    let onAdd: () -> Void
    let onKeepTalking: () -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text(draft.name).font(.headline)
                HStack(spacing: 10) {
                    Label(draft.estimatedHours.hoursLabel, systemImage: "clock")
                    EnergyBadge(cost: draft.energyCost)
                    Text(draft.category.label).foregroundStyle(.secondary)
                }
                .font(.callout)
                HStack {
                    Button("Not quite…", action: onKeepTalking)
                    Spacer()
                    Button("Review & Add", action: onAdd).buttonStyle(.borderedProminent)
                }
            }
            .padding(4)
        } label: {
            Label("Here's the task", systemImage: "sparkles")
        }
    }
}

extension TaskDraft: @retroactive Identifiable {
    public var id: String { "\(name)|\(estimatedHours)|\(energyCost)|\(category)" }
}
