import EventKit
import Foundation

/// Writes keyed lines into reminders' notes in Reminders.app (ticket 32). Nothing else about a
/// reminder is ever changed.
@MainActor
public struct AppleRemindersWriter: ReminderNotesWriting {
    public let store: EKEventStore
    private let calendar: Calendar

    public init(store: EKEventStore, calendar: Calendar = .current) {
        self.store = store
        self.calendar = calendar
    }

    public func updateNotes(externalID: String, changes: [ReminderNotes.Key: String?]) async throws -> ExternalReminder? {
        guard let reminder = find(externalID) else { return nil }
        let current = reminder.notes ?? ""
        let merged = ReminderNotes(current).merging(changes)
        if merged != current {
            reminder.notes = merged.isEmpty ? nil : merged
            try store.save(reminder, commit: true)
        }
        return ExternalReminder(
            externalID: externalID,
            sourceID: reminder.calendar.calendarIdentifier,
            title: reminder.title ?? "",
            due: AppleRemindersSource.dueDate(reminder.dueDateComponents, calendar: calendar),
            isCompleted: reminder.isCompleted,
            list: ListAssignment.infer(fromTitle: reminder.calendar.title),
            notes: reminder.notes ?? ""
        )
    }

    /// Links store the external identifier when there is one, else the local identifier.
    private func find(_ id: String) -> EKReminder? {
        let byExternal = store.calendarItems(withExternalIdentifier: id).compactMap { $0 as? EKReminder }
        return byExternal.first ?? store.calendarItem(withIdentifier: id) as? EKReminder
    }
}
