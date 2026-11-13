import EmoKit
import SwiftData
import SwiftUI

@main
struct EmoPhoneApp: App {
    private let container: ModelContainer

    init() {
        do {
            container = try EmoStore.makeContainer()
        } catch {
            fatalError("Could not open Emo's data store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            PhoneRootView()
        }
        .modelContainer(container)
    }
}

/// Tabs grow with the iPhone tickets (Today in 26, Week and Settings in 27).
struct PhoneRootView: View {
    var body: some View {
        TabView {
            Tab("Backlog", systemImage: "tray.full") {
                NavigationStack { PhoneBacklogView() }
            }
        }
    }
}
