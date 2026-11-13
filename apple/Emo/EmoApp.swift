import EmoKit
import SwiftData
import SwiftUI

@main
struct EmoApp: App {
    private let container: ModelContainer

    init() {
        do {
            container = try EmoStore.makeContainer()
        } catch {
            fatalError("Could not open Emo's data store: \(error)")
        }
    }

    var body: some Scene {
        // A single main window: Emo is one planner, and this frees ⌘N (File › New Window) for tasks.
        Window("Emo", id: "main") {
            RootView()
        }
        .modelContainer(container)
        .defaultSize(width: 900, height: 600)
        .commands { SectionCommands() }
    }
}

/// View › Today (⌘1) / Backlog (⌘2). Shares the selection with `RootView` through app storage.
private struct SectionCommands: Commands {
    @AppStorage(SidebarItem.storageKey) private var selection: SidebarItem = .today

    var body: some Commands {
        CommandGroup(before: .sidebar) {
            ForEach(Array(SidebarItem.allCases.enumerated()), id: \.element) { index, item in
                Button(item.title) { selection = item }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
            Divider()
        }
    }
}
