import Foundation
import SwiftData

/// Builds the app's SwiftData container. The single place that knows the schema and store location.
public enum EmoStore {
    public static let schema = Schema([TaskItem.self, CheckIn.self, CalendarEvent.self])

    public enum Location: Sendable {
        /// Default on-disk store in the app's Application Support container.
        case standard
        /// A specific file, e.g. a temp file in tests that simulates relaunching.
        case file(URL)
        /// Ephemeral, for previews and tests.
        case inMemory
    }

    public static func makeContainer(_ location: Location = .standard) throws -> ModelContainer {
        let configuration: ModelConfiguration
        switch location {
        case .standard:
            // CloudKit stays off until ticket 14; models are already CloudKit-compatible.
            configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        case .file(let url):
            configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        case .inMemory:
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        }
        return try ModelContainer(for: schema, configurations: configuration)
    }
}
