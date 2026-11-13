import Foundation

/// One reminder as an integration reports it.
public struct ExternalReminder: Equatable, Sendable {
    public var externalID: String
    public var sourceID: String
    public var title: String
    public var due: Date?
    public var isCompleted: Bool
    /// What the reminder's list is for, read from the list's name.
    public var list: ListAssignment

    public init(externalID: String, sourceID: String, title: String, due: Date? = nil, isCompleted: Bool = false,
                list: ListAssignment = ListAssignment(role: .nextAction)) {
        self.externalID = externalID
        self.sourceID = sourceID
        self.title = title
        self.due = due
        self.isCompleted = isCompleted
        self.list = list
    }

    /// Only the fields Emo mirrors (title, due, list role and area); completion is handled separately.
    var contentHash: String {
        [title, due.map { String($0.timeIntervalSinceReferenceDate) } ?? "-", list.role.rawValue, list.area ?? "-"]
            .joined(separator: "\u{1F}")
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
