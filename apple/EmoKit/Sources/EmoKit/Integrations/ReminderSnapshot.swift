import Foundation

/// One reminder as an integration reports it.
public struct ExternalReminder: Equatable, Sendable {
    public var externalID: String
    public var sourceID: String
    public var title: String
    public var due: Date?
    public var isCompleted: Bool
    /// When it was ticked, for completed reminders.
    public var completedAt: Date?
    /// What the reminder's list is for, read from the list's name.
    public var list: ListAssignment
    /// The reminder's notes, raw (see `ReminderNotes` for the keyed lines Emo reads).
    public var notes: String

    public init(externalID: String, sourceID: String, title: String, due: Date? = nil, isCompleted: Bool = false,
                completedAt: Date? = nil, list: ListAssignment = ListAssignment(role: .nextAction), notes: String = "") {
        self.externalID = externalID
        self.sourceID = sourceID
        self.title = title
        self.due = due
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.list = list
        self.notes = notes
    }

    /// Only the fields Emo mirrors (title, due, list role and area, notes); completion is handled
    /// separately. Notes join the hash only when present, so reminders without notes keep the hash
    /// they had before notes were imported (and aren't all re-synced once).
    var contentHash: String {
        var parts = [title, due.map { String($0.timeIntervalSinceReferenceDate) } ?? "-", list.role.rawValue, list.area ?? "-"]
        if !notes.isEmpty { parts.append(notes) }
        return parts.joined(separator: "\u{1F}")
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
