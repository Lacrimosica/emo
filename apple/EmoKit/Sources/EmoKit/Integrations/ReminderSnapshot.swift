import Foundation

/// One reminder as an integration reports it.
public struct ExternalReminder: Equatable, Sendable {
    public var externalID: String
    public var sourceID: String
    public var title: String
    public var due: Date?
    public var isCompleted: Bool

    public init(externalID: String, sourceID: String, title: String, due: Date? = nil, isCompleted: Bool = false) {
        self.externalID = externalID
        self.sourceID = sourceID
        self.title = title
        self.due = due
        self.isCompleted = isCompleted
    }

    /// Only the fields Emo mirrors (title, due); completion is handled separately.
    var contentHash: String {
        [title, due.map { String($0.timeIntervalSinceReferenceDate) } ?? "-"].joined(separator: "\u{1F}")
    }
}

/// Open reminders plus recently completed ones in `sources`. A linked reminder that's in neither
/// set was deleted upstream.
public struct ReminderSnapshot: Sendable {
    public var provider: String
    public var sources: Set<String>
    public var reminders: [ExternalReminder]

    public init(provider: String, sources: Set<String>, reminders: [ExternalReminder]) {
        self.provider = provider
        self.sources = sources
        self.reminders = reminders
    }
}
