import EmoKit
import SwiftData
import SwiftUI

/// Adds a standalone transit block (not tied to a task; planning works around it).
struct TransitSheet: View {
    let day: LocalDay
    let today: LocalDay

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var start = Date()
    @State private var minutes = 30
    @State private var note = ""
    @State private var errorMessage: String?

    var body: some View {
        Form {
            DatePicker("Leave at", selection: $start)
            Stepper(value: $minutes, in: 5...480, step: 5) {
                LabeledContent("Duration", value: "\(minutes) min")
            }
            TextField("Note", text: $note, prompt: Text("e.g. Drive to the office"))
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.callout)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 380)
        .navigationTitle("Add Transit")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Add", action: add) }
        }
        .onAppear {
            let calendar = Calendar.current
            start = day == today
                ? Date.now.addingTimeInterval(7.5 * 60).snapped(toMinutes: 15, calendar: calendar)
                : calendar.date(byAdding: .hour, value: 9, to: day.start(in: calendar))!
        }
    }

    private func add() {
        do {
            try CalendarEngine(context: modelContext).createTransit(start: start, duration: TimeInterval(minutes * 60), note: note)
            dismiss()
        } catch let error as CalendarEngine.EditError {
            errorMessage = error.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
