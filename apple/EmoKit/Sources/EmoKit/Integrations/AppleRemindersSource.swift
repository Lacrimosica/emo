import EventKit
import Foundation

/// Reads Reminders.app lists and reports snapshots for `ReminderReconciler`.
@MainActor
public final class AppleRemindersSource {
    public static let provider = "apple-reminders"
    /// Completed reminders are fetched back this far, so completions done while Emo was closed land.
    static let completedLookback: TimeInterval = 30 * 86_400

    public let store: EKEventStore

    public init(store: EKEventStore = EKEventStore()) {
        self.store = store
    }

    public static var hasAccess: Bool { EKEventStore.authorizationStatus(for: .reminder) == .fullAccess }

    public static var accessDenied: Bool {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .denied, .restricted, .writeOnly: true
        default: false
        }
    }

    public func requestAccess() async throws -> Bool {
        try await store.requestFullAccessToReminders()
    }

    public func lists() -> [AppleCalendarSource.CalendarInfo] {
        store.calendars(for: .reminder)
            .map { AppleCalendarSource.CalendarInfo(id: $0.calendarIdentifier, title: $0.title,
                                                    accountTitle: $0.source?.title ?? "Other", colorHex: "#FF9500") }
            .sorted { ($0.accountTitle, $0.title) < ($1.accountTitle, $1.title) }
    }

    public func snapshot(selected: Set<String>, now: Date = Date(), calendar: Calendar = .current) async -> ReminderSnapshot {
        let lists = store.calendars(for: .reminder).filter { selected.contains($0.calendarIdentifier) }
        guard !lists.isEmpty else { return ReminderSnapshot(provider: Self.provider, sources: selected, reminders: []) }
        let open = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: lists)
        let done = store.predicateForCompletedReminders(withCompletionDateStarting: now.addingTimeInterval(-Self.completedLookback),
                                                        ending: now, calendars: lists)
        let assignments = Dictionary(uniqueKeysWithValues: lists.map {
            ($0.calendarIdentifier, ListAssignment.infer(fromTitle: $0.title))
        })
        let reminders = await fetch(open, assignments, calendar: calendar) + fetch(done, assignments, calendar: calendar)
        return ReminderSnapshot(provider: Self.provider, sources: selected, reminders: reminders)
    }

    private func fetch(_ predicate: NSPredicate, _ assignments: [String: ListAssignment],
                       calendar: Calendar) async -> [ExternalReminder] {
        await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate,
                                 completion: Self.completion(assignments: assignments, calendar: calendar, continuation))
        }
    }

    /// EventKit calls this on a background queue, so it must not be main-actor isolated
    /// (a closure written inside this @MainActor class would be, and traps at runtime).
    /// Maps to value types here: EKReminder isn't Sendable.
    private nonisolated static func completion(
        assignments: [String: ListAssignment],
        calendar: Calendar,
        _ continuation: CheckedContinuation<[ExternalReminder], Never>
    ) -> @Sendable ([EKReminder]?) -> Void {
        { reminders in
            let mapped = (reminders ?? []).map { reminder in
                ExternalReminder(
                    externalID: reminder.calendarItemExternalIdentifier ?? reminder.calendarItemIdentifier,
                    sourceID: reminder.calendar.calendarIdentifier,
                    title: reminder.title ?? "",
                    due: dueDate(reminder.dueDateComponents, calendar: calendar),
                    isCompleted: reminder.isCompleted,
                    completedAt: reminder.completionDate,
                    list: assignments[reminder.calendar.calendarIdentifier] ?? ListAssignment(role: .nextAction),
                    notes: reminder.notes ?? ""
                )
            }
            continuation.resume(returning: mapped)
        }
    }

    /// A due date without a time means "by the end of that day".
    nonisolated static func dueDate(_ components: DateComponents?, calendar: Calendar) -> Date? {
        guard let components, let date = calendar.date(from: components) else { return nil }
        guard components.hour == nil else { return date }
        return calendar.date(bySettingHour: 23, minute: 59, second: 0, of: date)
    }
}
