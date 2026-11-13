import EmoKit
import SwiftUI

/// Settings › Integrations: which outside calendars feed Emo's internal calendar.
struct IntegrationsSettingsView: View {
    @Environment(CalendarSyncService.self) private var calendarSync
    @Environment(RemindersSyncService.self) private var remindersSync
    @Environment(\.openURL) private var openURL

    #if os(macOS)
    private static let device = "Mac"
    private static let calendarPrivacyURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!
    private static let remindersPrivacyURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")!
    #else
    private static let device = "iPhone"
    /// iOS can only open Emo's own page in Settings, which holds its Calendars and Reminders switches.
    private static let calendarPrivacyURL = URL(string: UIApplication.openSettingsURLString)!
    private static let remindersPrivacyURL = calendarPrivacyURL
    #endif

    var body: some View {
        Form {
            Section {
                Toggle("Apple Calendar", isOn: Binding(
                    get: { calendarSync.isEnabled },
                    set: { on in Task { await calendarSync.setEnabled(on) } }
                ))
                Text("Events from \(PlatformNames.calendarApp) (iCloud, Google, Exchange and other accounts on this \(Self.device)) appear in Emo as fixed events, and Emo plans around them. Changes in \(PlatformNames.calendarApp) show up automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if calendarSync.accessDenied {
                    AccessDeniedRow(message: "Emo doesn't have access to your calendars.") { openURL(Self.calendarPrivacyURL) }
                }
            }

            if calendarSync.isEnabled, calendarSync.hasAccess {
                ForEach(accounts, id: \.self) { account in
                    Section(account) {
                        ForEach(calendarSync.calendars.filter { $0.accountTitle == account }) { cal in
                            Toggle(isOn: Binding(
                                get: { calendarSync.selectedCalendars.contains(cal.id) },
                                set: { _ in calendarSync.toggle(cal.id) }
                            )) {
                                Label {
                                    Text(cal.title)
                                } icon: {
                                    Circle().fill(Color(hex: cal.colorHex)).frame(width: 10, height: 10)
                                }
                            }
                        }
                    }
                }

                WriteBackSettingsSection()

                Section {
                    HStack {
                        Button("Sync Now") { calendarSync.reloadCalendars(); calendarSync.sync() }
                        Spacer()
                        Text(status).font(.caption).foregroundStyle(.secondary)
                    }
                    if let error = calendarSync.errorMessage {
                        Text(error).font(.callout).foregroundStyle(.red)
                    }
                }
            }

            Section {
                Toggle("Apple Reminders", isOn: Binding(
                    get: { remindersSync.isEnabled },
                    set: { on in Task { await remindersSync.setEnabled(on) } }
                ))
                Text("Open reminders join your backlog with a quick default size (marked Review). Each list's role comes from its name (\"NA - Home\", \"SOMEDAY - Personal\", \"WAITING\"…): only next-action and daily checklist lists are scheduled; the rest are kept in the backlog but stay off your calendar. Completing or deleting one in Reminders updates Emo.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if remindersSync.accessDenied {
                    AccessDeniedRow(message: "Emo doesn't have access to your reminders.") { openURL(Self.remindersPrivacyURL) }
                }
            }
            if remindersSync.isEnabled, remindersSync.hasAccess {
                Section("Lists") {
                    ForEach(remindersSync.lists) { list in
                        let role = ListAssignment.infer(fromTitle: list.title).role
                        Toggle(isOn: Binding(
                            get: { remindersSync.selectedLists.contains(list.id) },
                            set: { _ in remindersSync.toggle(list.id) }
                        )) {
                            // Side by side on the Mac; stacked on a phone-width screen.
                            ViewThatFits(in: .horizontal) {
                                HStack {
                                    Text("\(list.title) · \(list.accountTitle)")
                                    Spacer()
                                    ListRoleLabel(role: role)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(list.title) · \(list.accountTitle)")
                                    ListRoleLabel(role: role)
                                }
                            }
                        }
                    }
                }
                Section {
                    HStack {
                        Button("Sync Now") { remindersSync.reloadLists(); remindersSync.sync() }
                        Spacer()
                        Text(remindersStatus).font(.caption).foregroundStyle(.secondary)
                    }
                    if let error = remindersSync.errorMessage {
                        Text(error).font(.callout).foregroundStyle(.red)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task {
            await calendarSync.ensureAccess()
            await remindersSync.ensureAccess()
        }
    }

    private var remindersStatus: String {
        guard let lastSync = remindersSync.lastSync else { return "Not synced yet" }
        var text = "Synced \(lastSync.formatted(date: .omitted, time: .shortened))"
        if let r = remindersSync.lastResult, r.changed {
            text += " · \(r.added) added, \(r.updated) changed, \(r.completed) completed, \(r.removed) removed"
        }
        return text
    }

    private var accounts: [String] {
        var seen: [String] = []
        for cal in calendarSync.calendars where !seen.contains(cal.accountTitle) { seen.append(cal.accountTitle) }
        return seen
    }

    private var status: String {
        guard let lastSync = calendarSync.lastSync else { return "Not synced yet" }
        var text = "Synced \(lastSync.formatted(date: .omitted, time: .shortened))"
        if let r = calendarSync.lastResult, r.changed {
            text += " · \(r.added) added, \(r.updated) changed, \(r.removed) removed"
        }
        return text
    }
}

private struct ListRoleLabel: View {
    let role: ListRole

    var body: some View {
        Label("\(role.label) · \(role.schedulingNote)", systemImage: role.systemImage)
            .font(.caption)
            .foregroundStyle(role.isSchedulable ? Color.secondary : Color.orange)
    }
}

/// Access was refused: say so and link to where the user can grant it.
private struct AccessDeniedRow: View {
    let message: String
    let openSettings: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Label(message, systemImage: "lock")
                Spacer()
                Button("Open Privacy Settings", action: openSettings)
            }
            VStack(alignment: .leading, spacing: 6) {
                Label(message, systemImage: "lock")
                Button("Open Settings", action: openSettings)
            }
        }
        .font(.callout)
    }
}

extension Color {
    /// "#RRGGBB" → Color.
    init(hex: String) {
        let value = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x888888
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}
