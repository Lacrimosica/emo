import EmoKit
import SwiftData
import SwiftUI

/// Edits one internal calendar event: a popover on the Mac, a sheet (inside a NavigationStack) on iPhone.
struct EventEditor: View {
    let event: CalendarEvent
    /// The event was just created to be edited here, so Cancel removes it again.
    var isNew = false

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var start = Date()
    @State private var end = Date()
    @State private var notes = ""
    @State private var isPinned = false
    @State private var errorMessage: String?

    private var isTaskBlock: Bool { event.kind == .taskBlock }

    var body: some View {
        Form {
            Group {
                if isTaskBlock {
                    Text(event.title).font(.headline)
                } else {
                    TextField("Title", text: $title)
                        .font(.headline)
                }
                DatePicker("Starts", selection: $start)
                DatePicker("Ends", selection: $end)
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(2...5)
                if isTaskBlock {
                    Toggle("Pinned", isOn: $isPinned)
                        .help("Pinned blocks stay put when Emo re-plans")
                    #if os(macOS)
                    HStack {
                        Button("Complete Task", systemImage: "checkmark.circle") { run(.completeTask) }
                        Button("Skip Today", systemImage: "forward") { run(.skipToday) }
                    }
                    #else
                    Button("Complete Task", systemImage: "checkmark.circle") { run(.completeTask) }
                    Button("Skip for Today", systemImage: "forward") { run(.skipToday) }
                    #endif
                }
            }
            .disabled(!event.isUserEditable)

            if !event.isUserEditable {
                Label("This event comes from an integration and can only be changed there.", systemImage: "link")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let errorMessage {
                Text(errorMessage).font(.callout).foregroundStyle(.red)
            }

            #if os(macOS)
            HStack {
                Button(isTaskBlock ? "Remove Block" : "Delete", role: .destructive, action: delete)
                Spacer()
                Button("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
            }
            .disabled(!event.isUserEditable)
            #else
            if event.isUserEditable, !isNew {
                Section {
                    Button(isTaskBlock ? "Remove Block" : "Delete Event", role: .destructive, action: delete)
                }
            }
            #endif
        }
        .formStyle(.grouped)
        #if os(macOS)
        .frame(width: 340)
        .disabled(!event.isUserEditable)
        #else
        .navigationTitle(isNew ? "New Event" : isTaskBlock ? "Task Block" : "Edit Event")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: cancel) }
            ToolbarItem(placement: .confirmationAction) {
                Button(isNew ? "Add" : "Save", action: save).disabled(!event.isUserEditable)
            }
        }
        .interactiveDismissDisabled(isNew)
        #endif
        .onAppear {
            title = event.title
            start = event.start
            end = event.end
            notes = event.notes
            isPinned = event.isLocked
        }
    }

    private var engine: CalendarEngine { CalendarEngine(context: modelContext) }

    private func save() {
        do {
            try engine.update(event, title: isTaskBlock ? nil : title, notes: notes, start: start, end: end)
            // An explicit choice in the editor wins over "moved by hand → pinned".
            if isTaskBlock, event.isLocked != isPinned { try engine.setPinned(event, isPinned) }
            dismiss()
        } catch let error as CalendarEngine.EditError {
            errorMessage = error.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func cancel() {
        if isNew { try? engine.delete(event) }
        dismiss()
    }

    private func run(_ action: TaskBlockAction) {
        do {
            try TaskBlockActions.perform(action, on: event, in: modelContext)
            dismiss()
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
