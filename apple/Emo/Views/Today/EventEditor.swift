import EmoKit
import SwiftData
import SwiftUI

/// Popover for editing one internal calendar event.
struct EventEditor: View {
    let event: CalendarEvent

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var start = Date()
    @State private var end = Date()
    @State private var notes = ""
    @State private var errorMessage: String?

    var body: some View {
        Form {
            TextField("Title", text: $title)
                .font(.headline)
            DatePicker("Starts", selection: $start)
            DatePicker("Ends", selection: $end)
            TextField("Notes", text: $notes, axis: .vertical)
                .lineLimit(2...5)

            if !event.isUserEditable {
                Label("This event comes from an integration and can only be changed there.", systemImage: "link")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let errorMessage {
                Text(errorMessage).font(.callout).foregroundStyle(.red)
            }

            HStack {
                Button("Delete", role: .destructive, action: delete)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
            }
            .disabled(!event.isUserEditable)
        }
        .formStyle(.grouped)
        .frame(width: 340)
        .disabled(!event.isUserEditable)
        .onAppear {
            title = event.title
            start = event.start
            end = event.end
            notes = event.notes
        }
    }

    private var engine: CalendarEngine { CalendarEngine(context: modelContext) }

    private func save() {
        do {
            try engine.update(event, title: title, notes: notes, start: start, end: end)
            dismiss()
        } catch let error as CalendarEngine.EditError {
            errorMessage = error.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete() {
        do {
            try engine.delete(event)
            dismiss()
        } catch {
            errorMessage = (error as? CalendarEngine.EditError)?.message ?? error.localizedDescription
        }
    }
}

extension CalendarEngine.EditError {
    var message: String {
        switch self {
        case .emptyTitle: "Give the event a title."
        case .endNotAfterStart: "The end must be after the start."
        case .tooShort: "Events must be at least 5 minutes long."
        case .notUserEditable: "This event comes from an integration and can't be edited here."
        }
    }
}
