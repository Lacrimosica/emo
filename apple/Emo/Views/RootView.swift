import EmoKit
import SwiftData
import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case today
    case backlog

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .backlog: "Backlog"
        }
    }

    var systemImage: String {
        switch self {
        case .today: "sun.max"
        case .backlog: "tray.full"
        }
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @State private var selection: SidebarItem? = .today
    @State private var today = LocalDay.today()
    @State private var isCheckingIn = false
    /// Days the user dismissed the prompt with "Later", so it doesn't nag again until tomorrow.
    @State private var promptDismissedFor: LocalDay?

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.title, systemImage: item.systemImage)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 190)
        } detail: {
            switch selection {
            case .today, nil:
                TodayView(day: today, isCheckingIn: $isCheckingIn)
            case .backlog:
                BacklogView()
            }
        }
        .sheet(isPresented: $isCheckingIn, onDismiss: { promptDismissedFor = today }) {
            CheckInSheet(day: today)
        }
        .task(id: today) { promptForCheckInIfNeeded() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshToday() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            refreshToday()
        }
    }

    private func refreshToday() {
        let now = LocalDay.today()
        if now != today { today = now }
    }

    private func promptForCheckInIfNeeded() {
        guard promptDismissedFor != today, !isCheckingIn else { return }
        let existing = try? CheckIns(context: modelContext).checkIn(for: today)
        if existing == nil { isCheckingIn = true }
    }
}
