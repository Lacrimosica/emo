import EmoKit
import SwiftData
import SwiftUI

/// Puts a task at a chosen time as a pinned block that re-planning won't move.
struct PinTaskSheet: View {
    let task: TaskItem

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var start = Date.now.addingTimeInterval(7.5 * 60).snapped(toMinutes: 15)
    @State private var durationHours = 1.0
    @State private var errorMessage: String?

    var body: some View {
        Form {
            LabeledContent("Task", value: task.name)
            DatePicker("Starts", selection: $start)
            Stepper(value: $durationHours, in: 0.25...12, step: 0.25) {
                LabeledContent("Duration", value: durationHours.hoursLabel)
            }
            LabeledContent("Ends", value: end.formatted(date: .omitted, time: .shortened))
            Text("Pinned blocks stay put when Emo re-plans.")
                .font(.callout)
                .foregroundStyle(.secondary)
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.callout)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 400)
        .navigationTitle("Schedule Task")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Pin", action: pin)
            }
        }
        .onAppear { durationHours = min(max(task.estimatedHours, 0.25), 12) }
    }

    private var end: Date { start.addingTimeInterval(durationHours * 3600) }

    private func pin() {
        do {
            try TaskLifecycle(context: modelContext).pin(task, start: start, end: end)
            dismiss()
        } catch let error as CalendarEngine.EditError {
            errorMessage = error.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
