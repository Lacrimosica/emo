import Foundation
import SwiftData

/// The only writer of Emo's internal calendar. Views, the scheduler and (later) the integration
/// reconciler all change events through here, so invariants live in one place.
@MainActor
public struct CalendarEngine {
    /// Shortest event the engine accepts.
    public static let minimumDuration: TimeInterval = 5 * 60

    public enum EditError: Error, Equatable {
        case emptyTitle
        case endNotAfterStart
        case tooShort
        /// Linked events mirror an integration; only the reconciler may change them.
        case notUserEditable
    }

    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    // MARK: Reading

    /// Events overlapping `day` (including ones that cross midnight), earliest first.
    public func events(on day: LocalDay, calendar: Calendar = .current) throws -> [CalendarEvent] {
        try context.fetch(Self.descriptor(for: day, calendar: calendar))
    }

    /// Shared with SwiftUI's `@Query` so views show exactly what the engine reads.
    public static func descriptor(for day: LocalDay, calendar: Calendar = .current) -> FetchDescriptor<CalendarEvent> {
        let dayStart = day.start(in: calendar)
        let dayEnd = day.end(in: calendar)
        return FetchDescriptor(
            predicate: #Predicate { $0.start < dayEnd && $0.end > dayStart },
            sortBy: [SortDescriptor(\.start), SortDescriptor(\.end)]
        )
    }

    // MARK: User edits (local fixed events)

    @discardableResult
    public func createFixedEvent(
        title: String,
        start: Date,
        end: Date,
        notes: String = "",
        now: Date = Date()
    ) throws -> CalendarEvent {
        let title = try Self.validated(title: title)
        try Self.validate(start: start, end: end)
        let event = CalendarEvent(title: title, start: start, end: end, kind: .fixed, notes: notes, now: now)
        context.insert(event)
        try context.save()
        return event
    }

    /// Edits any of an event's user-facing fields. Unspecified fields are left as they are.
    public func update(
        _ event: CalendarEvent,
        title: String? = nil,
        notes: String? = nil,
        start: Date? = nil,
        end: Date? = nil,
        now: Date = Date()
    ) throws {
        guard event.isUserEditable else { throw EditError.notUserEditable }
        let newTitle = try title.map(Self.validated(title:)) ?? event.title
        let newStart = start ?? event.start
        let newEnd = end ?? event.end
        try Self.validate(start: newStart, end: newEnd)

        event.title = newTitle
        if let notes { event.notes = notes }
        event.start = newStart
        event.end = newEnd
        event.updatedAt = now
        try context.save()
    }

    /// Moves an event to start at `newStart`, keeping its duration.
    public func move(_ event: CalendarEvent, to newStart: Date, now: Date = Date()) throws {
        try update(event, start: newStart, end: newStart.addingTimeInterval(event.duration), now: now)
    }

    public func delete(_ event: CalendarEvent) throws {
        guard event.isUserEditable else { throw EditError.notUserEditable }
        context.delete(event)
        try context.save()
    }

    // MARK: Validation

    private static func validated(title: String) throws(EditError) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .emptyTitle }
        return trimmed
    }

    private static func validate(start: Date, end: Date) throws(EditError) {
        guard end > start else { throw .endNotAfterStart }
        guard end.timeIntervalSince(start) >= minimumDuration else { throw .tooShort }
    }
}

extension Date {
    /// Rounds to the nearest multiple of `minutes` within the hour, in `calendar`'s timezone.
    public func snapped(toMinutes minutes: Int, calendar: Calendar = .current) -> Date {
        let step = TimeInterval(minutes * 60)
        let hourStart = calendar.dateInterval(of: .hour, for: self)!.start
        let offset = timeIntervalSince(hourStart)
        return hourStart.addingTimeInterval((offset / step).rounded() * step)
    }
}
