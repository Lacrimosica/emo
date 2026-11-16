import EmoKit
import SwiftData
import SwiftUI

/// Settings › AI › Memory: the short facts Emo knows about the user (ticket 21). Emo suggests them
/// while clarifying; here they can be read, edited, added and removed.
struct MemorySettingsSection: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MemoryNote.createdAt) private var notes: [MemoryNote]
    @State private var newNote = ""
    @State private var errorMessage: String?

    var body: some View {
        Section {
            ForEach(notes) { note in
                NoteRow(note: note, onCommit: { save(note, $0) }, onDelete: { delete(note) })
            }
            HStack {
                TextField("Add a note", text: $newNote, prompt: Text("e.g. Poli = university"))
                    .onSubmit(add)
                Button("Add", action: add)
                    .disabled(newNote.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let errorMessage {
                Text(errorMessage).font(.callout).foregroundStyle(.red)
            }
        } header: {
            Text("Memory")
        } footer: {
            Text("Short facts Emo uses when it clarifies tasks. They stay on your devices; when a cloud provider is selected, only the notes related to the conversation are sent.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var memory: AIMemory { AIMemory(context: modelContext) }

    private func add() {
        perform { _ = try memory.add(newNote) }
        newNote = ""
    }

    private func save(_ note: MemoryNote, _ text: String) {
        guard text != note.text else { return }
        perform { try memory.update(note, text: text) }
    }

    private func delete(_ note: MemoryNote) {
        perform { try memory.delete(note) }
    }

    private func perform(_ change: () throws -> Void) {
        do {
            try change()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// One editable note; the edit is saved on Return or when the field loses focus.
private struct NoteRow: View {
    let note: MemoryNote
    let onCommit: (String) -> Void
    let onDelete: () -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack {
            TextField("Note", text: $text)
                .labelsHidden()
                .focused($focused)
                .onSubmit { onCommit(text) }
                .onChange(of: focused) { _, isFocused in if !isFocused { onCommit(text) } }
            Button("Delete", systemImage: "minus.circle", role: .destructive, action: onDelete)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                .help("Forget this note")
        }
        .onAppear { text = note.text }
        .onChange(of: note.text) { _, saved in text = saved }
    }
}
