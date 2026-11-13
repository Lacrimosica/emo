import EmoKit
import SwiftData
import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case today
    case week
    case backlog

    var id: String { rawValue }
    static let storageKey = "sidebarSelection"

    var title: String {
        switch self {
        case .today: "Today"
        case .week: "Week"
        case .backlog: "Backlog"
        }
    }

    var systemImage: String {
        switch self {
        case .today: "sun.max"
        case .week: "calendar"
        case .backlog: "tray.full"
        }
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(CalendarSyncService.self) private var calendarSync

    @AppStorage(SidebarItem.storageKey) private var storedSelection: SidebarItem = .today
    @State private var today = LocalDay.today()
    @State private var displayedDay = LocalDay.today()
    @State private var weekStart = LocalDay.today().startOfWeek()
    /// The day whose check-in sheet is open, if any.
    @State private var checkInDay: LocalDay?
    /// The day the user dismissed the automatic prompt, so it doesn't nag again until tomorrow.
    @State private var promptDismissedFor: LocalDay?

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: selection) { item in
                Label(item.title, systemImage: item.systemImage)
                    // The selection is a SidebarItem; without this tag rows are tagged with their
                    // String `id`, which never matches, so clicks did nothing.
                    .tag(item)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 190)
        } detail: {
            switch storedSelection {
            case .today:
                TodayView(
                    day: displayedDay,
                    today: today,
                    onChangeDay: { displayedDay = $0 },
                    onCheckIn: { checkInDay = displayedDay }
                )
            case .week:
                WeekView(
                    weekStart: weekStart,
                    today: today,
                    onChangeWeek: { weekStart = $0 },
                    onOpenDay: { day in
                        displayedDay = day
                        storedSelection = .today
                    }
                )
            case .backlog:
                BacklogView()
            }
        }
        .sheet(item: $checkInDay, onDismiss: { promptDismissedFor = today }) { day in
            CheckInSheet(day: day)
        }
        .task(id: today) { promptForCheckInIfNeeded() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshToday(); calendarSync.sync() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            refreshToday()
        }
    }

    /// The sidebar's optional selection, backed by app storage (a click on empty space keeps the current item).
    private var selection: Binding<SidebarItem?> {
        Binding(get: { storedSelection }, set: { if let new = $0 { storedSelection = new } })
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
