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
        // The built-in categories, on first launch. Names fall back to the defaults if this fails.
        try? CategoryCatalog(context: container.mainContext).seedBuiltInsIfNeeded()
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

enum PhoneTab: String, CaseIterable, Hashable, Identifiable {
    case today, week, backlog, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .week: "Week"
        case .backlog: "Backlog"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .today: "sun.max"
        case .week: "calendar"
        case .backlog: "tray.full"
        case .settings: "gear"
        }
    }
}

/// Root of the iOS app. On iPhone, and on iPad when the window is narrow (Slide Over, a thin
/// Split View), it's a tab bar. On a full-width iPad window it's a sidebar like the Mac app's.
/// Both layouts share the same state, so resizing the window keeps the day you're looking at.
struct PhoneRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
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
        Group {
            if horizontalSizeClass == .regular {
                sidebarLayout
            } else {
                tabLayout
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

    private var tabLayout: some View {
        TabView(selection: $selectedTab) {
            ForEach(PhoneTab.allCases) { tab in
                Tab(tab.title, systemImage: tab.systemImage, value: tab) {
                    NavigationStack { screen(for: tab) }
                }
            }
        }
    }

    private var sidebarLayout: some View {
        NavigationSplitView {
            List(PhoneTab.allCases, selection: sidebarSelection) { tab in
                Label(tab.title, systemImage: tab.systemImage).tag(tab)
            }
            .navigationTitle("Emo")
        } detail: {
            // A fresh stack per section, so a pushed settings page doesn't linger after you switch.
            NavigationStack { screen(for: selectedTab) }
                .id(selectedTab)
        }
    }

    /// The sidebar's optional selection; tapping empty space keeps the current section.
    private var sidebarSelection: Binding<PhoneTab?> {
        Binding(get: { selectedTab }, set: { if let new = $0 { selectedTab = new } })
    }

    @ViewBuilder
    private func screen(for tab: PhoneTab) -> some View {
        switch tab {
        case .today:
            PhoneTodayView(
                day: displayedDay,
                today: today,
                onChangeDay: { displayedDay = $0 },
                onCheckIn: { checkInDay = displayedDay }
            )
        case .week:
            PhoneWeekView(
                weekStart: weekStart,
                today: today,
                onChangeWeek: { weekStart = $0 },
                onOpenDay: { day in
                    displayedDay = day
                    selectedTab = .today
                }
            )
        case .backlog:
            PhoneBacklogView()
        case .settings:
            PhoneSettingsView()
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
