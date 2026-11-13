import EmoKit
import SwiftData
import SwiftUI

/// Creates a new task, or edits an existing one (re-planning the days it's scheduled on).
struct TaskEditorSheet: View {
    /// nil to create a new task.
    let task: TaskItem?
    /// Pre-filled values for a new task (e.g. proposed by the assistant).
    var initialDraft: TaskDraft? = nil
    /// Called after a successful save.
    var onSaved: () -> Void = {}

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    /// Present in both apps; used to write the `ongoing:` line back for tasks from Reminders.
    @Environment(RemindersSyncService.self) private var remindersSync: RemindersSyncService?

    @State private var draft = TaskDraft()
    @State private var hasDeadline = false
    @State private var deadline = Calendar.current.startOfDay(for: .now).addingTimeInterval(86_400)
    @State private var errorMessage: String?

    var body: some View {
        Form {
            TextField("Name", text: $draft.name, prompt: Text("What needs doing?"))

            Section {
                Toggle("Ongoing", isOn: $draft.isOngoing.animation())
                if draft.isOngoing {
                    Stepper(value: $draft.sessionsPerWeek, in: 1...14) {
                        LabeledContent("Sessions a week", value: "\(draft.sessionsPerWeek)")
                    }
                    Stepper(value: $draft.sessionHours, in: 0.25...12, step: 0.25) {
                        LabeledContent("Session length", value: draft.sessionHours.hoursLabel)
                    }
                } else {
                    Stepper(value: $draft.estimatedHours, in: 0.25...24, step: 0.25) {
                        LabeledContent("Estimate", value: draft.estimatedHours.hoursLabel)
                    }
                }
            } footer: {
                if draft.isOngoing {
                    Text("A practice, not a one-off: Emo spreads the sessions over the week, each done session counts, and the task stays until you stop it.")
                }
            }

            Picker("Energy", selection: $draft.energyCost) {
                ForEach(EnergyCost.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            Picker("Category", selection: $draft.category) {
                ForEach(TaskCategory.allCases) { Text($0.label).tag($0) }
            }

            if !draft.isOngoing {
                Picker("Repeats", selection: $draft.recurrence) {
                    ForEach(Recurrence.allCases) { Text($0.label).tag($0) }
                }
            }

            Toggle("Needs travel", isOn: $draft.requiresTransit.animation())
            if draft.requiresTransit {
                Stepper(value: $draft.transitMinutes, in: 5...480, step: 5) {
                    LabeledContent("Travel time", value: "\(draft.transitMinutes) min")
                }
            }

            Toggle("Deadline", isOn: $hasDeadline)
            if hasDeadline {
                DatePicker("Due", selection: $deadline)
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.callout)
            }
        }
        .formStyle(.grouped)
        #if os(macOS)
        .frame(minWidth: 420)
        #endif
        .navigationTitle(task == nil ? "New Task" : "Edit Task")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(task == nil ? "Add" : "Save", action: save)
                    .disabled(!draft.isValid)
            }
        }
        .onChange(of: draft.requiresTransit) { _, on in
            if on, draft.transitMinutes < 5 { draft.transitMinutes = 20 }
        }
        .onAppear {
            if task == nil, let initialDraft { draft = initialDraft }
            guard let task else { return }
            draft = TaskDraft(task)
            if let existing = task.deadline {
                hasDeadline = true
                deadline = existing
            }
        }
    }

    private func save() {
        var final = draft
        final.deadline = hasDeadline ? deadline : nil
        do {
            if let task {
                let ongoingBefore = task.isOngoing ? task.ongoingNotesValue : nil
                try TaskLifecycle(context: modelContext).update(task, with: final)
                let ongoingAfter = task.isOngoing ? task.ongoingNotesValue : nil
                // For a task from Reminders the notes are the source of truth: write `ongoing:` back.
                if ongoingAfter != ongoingBefore, let remindersSync,
                   ReminderNotesWriteBack(context: modelContext).hasLinkedReminder(task) {
                    Task { await remindersSync.writeNotes([.ongoing: ongoingAfter], for: task) }
                }
            } else {
                try Backlog(context: modelContext).add(final)
            }
            dismiss()
            onSaved()
        } catch {
            errorMessage = "Couldn't save the task: \(error.localizedDescription)"
        }
    }
}

#Preview {
    TaskEditorSheet(task: nil)
        .modelContainer(try! EmoStore.makeContainer(.inMemory))
}
