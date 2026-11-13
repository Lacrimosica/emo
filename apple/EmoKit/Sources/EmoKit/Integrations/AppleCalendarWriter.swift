import EventKit
import Foundation

/// Applies `CalendarWriteBack` operations to a dedicated "Emo" calendar in Calendar.app.
/// It decides nothing itself: the engine computes the operations.
@MainActor
public final class AppleCalendarWriter {
    public static let calendarTitle = "Emo"

    private let store: EKEventStore

    public init(store: EKEventStore) {
        self.store = store
    }

    /// The Emo calendar, found by stored identifier or title, created on first use.
    public func emoCalendar(knownID: String?) throws -> EKCalendar {
        if let knownID, let cal = store.calendar(withIdentifier: knownID), cal.allowsContentModifications { return cal }
        if let existing = store.calendars(for: .event).first(where: { $0.title == Self.calendarTitle && $0.allowsContentModifications }) {
            return existing
        }
        let cal = EKCalendar(for: .event, eventStore: store)
        cal.title = Self.calendarTitle
        cal.cgColor = CGColor(red: 0.55, green: 0.35, blue: 0.85, alpha: 1)
        guard let source = store.defaultCalendarForNewEvents?.source
                ?? store.sources.first(where: { $0.sourceType == .local }) else {
            throw LLMError.transport("No calendar account available to hold the Emo calendar.")
        }
        cal.source = source
        try store.saveCalendar(cal, commit: true)
        return cal
    }

    /// Applies `operations` and returns what to record for each (with the external ID of anything
    /// created). An update whose event was deleted in Calendar.app becomes delete + create.
    public func apply(_ operations: [CalendarWriteBack.Operation], in calendar: EKCalendar)
        throws -> [(CalendarWriteBack.Operation, String?)] {
        var applied: [(CalendarWriteBack.Operation, String?)] = []
        for op in operations {
            switch op {
            case .create(let block):
                applied.append((op, try create(block, in: calendar)))
            case .update(let id, let block):
                if let event = store.calendarItem(withIdentifier: id) as? EKEvent {
                    fill(event, with: block)
                    try store.save(event, span: .thisEvent, commit: false)
                    applied.append((op, nil))
                } else {
                    applied.append((.delete(externalID: id), nil))
                    applied.append((.create(block), try create(block, in: calendar)))
                }
            case .delete(let id):
                if let event = store.calendarItem(withIdentifier: id) as? EKEvent {
                    try store.remove(event, span: .thisEvent, commit: false)
                }
                applied.append((op, nil))
            }
        }
        try store.commit()
        return applied
    }

    /// Deletes the Emo calendar and everything in it.
    public func removeCalendar(knownID: String?) throws {
        guard let knownID, let cal = store.calendar(withIdentifier: knownID) else { return }
        try store.removeCalendar(cal, commit: true)
    }

    private func create(_ block: CalendarWriteBack.OutboundEvent, in calendar: EKCalendar) throws -> String {
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        fill(event, with: block)
        try store.save(event, span: .thisEvent, commit: false)
        return event.calendarItemIdentifier
    }

    private func fill(_ event: EKEvent, with block: CalendarWriteBack.OutboundEvent) {
        event.title = block.title
        event.startDate = block.start
        event.endDate = block.end
        event.notes = "Planned by Emo"
    }
}
