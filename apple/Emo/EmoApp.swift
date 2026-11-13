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
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
        .defaultSize(width: 900, height: 600)
    }
}
