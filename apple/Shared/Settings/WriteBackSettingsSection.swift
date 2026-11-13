import EmoKit
import SwiftUI

/// "Show Emo's plan in Calendar.app": mirrors planned task blocks into an "Emo" calendar.
struct WriteBackSettingsSection: View {
    @Environment(CalendarSyncService.self) private var calendarSync
    @State private var confirmingOff = false

    var body: some View {
        Section {
            Toggle("Show my plan in \(PlatformNames.calendarApp)", isOn: Binding(
                get: { calendarSync.isWriteBackEnabled },
                set: { on in
                    if on { Task { await calendarSync.setWriteBack(true) } } else { confirmingOff = true }
                }
            ))
            Text("Emo's planned task and travel blocks for the next two weeks appear in an “Emo” calendar and update as Emo re-plans. Emo never imports that calendar.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .confirmationDialog("Stop showing your plan in \(PlatformNames.calendarApp)?", isPresented: $confirmingOff) {
            Button("Remove the Emo Calendar", role: .destructive) { Task { await calendarSync.setWriteBack(false, removeExisting: true) } }
            Button("Keep Its Events") { Task { await calendarSync.setWriteBack(false, removeExisting: false) } }
        } message: {
            Text("You can delete the Emo calendar and its events, or leave them in \(PlatformNames.calendarApp).")
        }
    }
}
