import EmoKit
import SwiftData
import SwiftUI

/// Creates a new task, or edits an existing one (re-planning the days it's scheduled on).
struct TaskEditorSheet: View {
    /// nil to create a new task.
    let task: TaskItem?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var draft = TaskDraft()
    @State private var hasDeadline = false
    @State private var deadline = Calendar.current.startOfDay(for: .now).addingTimeInterval(86_400)
    @State private var errorMessage: String?

    var body: some View {
        Form {
            TextField("Name", text: $draft.name, prompt: Text("What needs doing?"))

            Stepper(value: $draft.estimatedHours, in: 0.25...24, step: 0.25) {
                LabeledContent("Estimate", value: draft.estimatedHours.hoursLabel)
            }

            Picker("Energy", selection: $draft.energyCost) {
                ForEach(EnergyCost.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            Picker("Category", selection: $draft.category) {
                ForEach(TaskCategory.allCases) { Text($0.label).tag($0) }
            }

            Picker("Repeats", selection: $draft.recurrence) {
                ForEach(Recurrence.allCases) { Text($0.label).tag($0) }
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
        .frame(minWidth: 420)
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
                try TaskLifecycle(context: modelContext).update(task, with: final)
            } else {
                try Backlog(context: modelContext).add(final)
            }
            dismiss()
        } catch {
            errorMessage = "Couldn't save the task: \(error.localizedDescription)"
        }
    }
}

#Preview {
    TaskEditorSheet(task: nil)
        .modelContainer(try! EmoStore.makeContainer(.inMemory))
}
