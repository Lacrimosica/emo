import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case backlog

    var id: String { rawValue }

    var title: String {
        switch self {
        case .backlog: "Backlog"
        }
    }

    var systemImage: String {
        switch self {
        case .backlog: "tray.full"
        }
    }
}

struct RootView: View {
    @State private var selection: SidebarItem? = .backlog

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.title, systemImage: item.systemImage)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 190)
        } detail: {
            switch selection {
            case .backlog, nil:
                BacklogView()
            }
        }
    }
}
