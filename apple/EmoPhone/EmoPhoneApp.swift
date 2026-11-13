import EmoKit
import SwiftData
import SwiftUI

@main
struct EmoPhoneApp: App {
    private let container: ModelContainer
    @State private var calendarSync: CalendarSyncService
    @State private var remindersSync: RemindersSyncService

    init() {
        let container: ModelContainer
        do {
            container = try EmoStore.makeContainer()
        } catch {
            fatalError("Could not open Emo's data store: \(error)")
        }
        self.container = container
        // Data is local to the phone (no iCloud yet, ticket 14), so the phone imports from
        // Calendar and Reminders itself; the reconcilers keep one copy per item on this device.
        _calendarSync = State(initialValue: CalendarSyncService(context: container.mainContext))
        _remindersSync = State(initialValue: RemindersSyncService(context: container.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            PhoneRootView()
                .environment(calendarSync)
                .environment(remindersSync)
        }
        .modelContainer(container)
    }
}

enum PhoneTab: Hashable { case today, week, backlog, settings }

struct PhoneRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(CalendarSyncService.self) private var calendarSync
    @Environment(RemindersSyncService.self) private var remindersSync

    @State private var today = LocalDay.today()
    @State private var displayedDay = LocalDay.today()
    @State private var weekStart = LocalDay.today().startOfWeek()
    @State private var selectedTab: PhoneTab = .today
    /// The day whose check-in sheet is open, if any.
    @State private var checkInDay: LocalDay?
    /// The day the user dismissed the automatic prompt, so it doesn't nag again until tomorrow.
    @State private var promptDismissedFor: LocalDay?

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Today", systemImage: "sun.max", value: .today) {
                NavigationStack {
                    PhoneTodayView(
                        day: displayedDay,
                        today: today,
                        onChangeDay: { displayedDay = $0 },
                        onCheckIn: { checkInDay = displayedDay }
                    )
                }
            }
            Tab("Week", systemImage: "calendar", value: .week) {
                NavigationStack {
                    PhoneWeekView(
                        weekStart: weekStart,
                        today: today,
                        onChangeWeek: { weekStart = $0 },
                        onOpenDay: { day in
                            displayedDay = day
                            selectedTab = .today
                        }
                    )
                }
            }
            Tab("Backlog", systemImage: "tray.full", value: .backlog) {
                NavigationStack { PhoneBacklogView() }
            }
            Tab("Settings", systemImage: "gear", value: .settings) {
                NavigationStack { PhoneSettingsView() }
            }
        }
        .sheet(item: $checkInDay, onDismiss: { promptDismissedFor = today }) { day in
            CheckInSheet(day: day)
        }
        .task(id: today) { promptForCheckInIfNeeded() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshToday(); calendarSync.sync(); remindersSync.sync() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            refreshToday()
        }
    }

    private func refreshToday() {
        let now = LocalDay.today()
        guard now != today else { return }
        if displayedDay == today { displayedDay = now }
        if weekStart == today.startOfWeek() { weekStart = now.startOfWeek() }
        today = now
        calendarSync.sync()   // the 14-day window moved
    }

    private func promptForCheckInIfNeeded() {
        guard promptDismissedFor != today, checkInDay == nil else { return }
        let existing = try? CheckIns(context: modelContext).checkIn(for: today)
        if existing == nil { checkInDay = today }
    }
}
