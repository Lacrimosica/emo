import EmoKit
import SwiftData
import SwiftUI

struct AddTaskSheet: View {
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
        .navigationTitle("New Task")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add", action: save)
                    .disabled(!draft.isValid)
            }
        }
    }

    private func save() {
        var final = draft
        final.deadline = hasDeadline ? deadline : nil
        do {
            try Backlog(context: modelContext).add(final)
            dismiss()
        } catch {
            errorMessage = "Couldn't save the task: \(error.localizedDescription)"
        }
    }
}

#Preview {
    AddTaskSheet()
        .modelContainer(try! EmoStore.makeContainer(.inMemory))
}
