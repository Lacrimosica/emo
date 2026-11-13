import EventKit
import Foundation

/// Reads Calendar.app (every account the Mac has: iCloud, Google, Exchange, subscriptions…) and
/// reports snapshots. It never writes Emo's internal calendar; `CalendarReconciler` does.
@MainActor
public final class AppleCalendarSource {
    public static let provider = "apple-calendar"

    public struct CalendarInfo: Identifiable, Hashable, Sendable {
        public let id: String
        public let title: String
        public let accountTitle: String
        public let colorHex: String
    }

    public let store: EKEventStore

    public init(store: EKEventStore = EKEventStore()) {
        self.store = store
    }

    public static var hasAccess: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    public static var accessDenied: Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .denied, .restricted, .writeOnly: true
        default: false
        }
    }

    /// Shows the system permission prompt the first time.
    public func requestAccess() async throws -> Bool {
        try await store.requestFullAccessToEvents()
    }

    public func calendars() -> [CalendarInfo] {
        store.calendars(for: .event)
            .map { CalendarInfo(id: $0.calendarIdentifier, title: $0.title, accountTitle: $0.source?.title ?? "Other",
                                colorHex: Self.hex($0.cgColor)) }
            .sorted { ($0.accountTitle, $0.title) < ($1.accountTitle, $1.title) }
    }

    /// Every event in `selected` calendars from the start of `day` for `days` days.
    public func snapshot(selected: Set<String>, from day: LocalDay, days: Int = 14, calendar: Calendar = .current) -> CalendarSnapshot {
        let window = DateInterval(start: day.start(in: calendar), end: day.adding(days: days, calendar: calendar).start(in: calendar))
        let calendars = store.calendars(for: .event).filter { selected.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else {
            return CalendarSnapshot(provider: Self.provider, sources: selected, window: window, events: [])
        }
        let predicate = store.predicateForEvents(withStart: window.start, end: window.end, calendars: calendars)
        let events = store.events(matching: predicate).compactMap { event -> ExternalEvent? in
            guard let start = event.startDate, let end = event.endDate else { return nil }
            return ExternalEvent(
                externalID: Self.externalID(event),
                sourceID: event.calendar.calendarIdentifier,
                title: event.title ?? "",
                start: start,
                end: end,
                isAllDay: event.isAllDay,
                notes: event.location ?? ""
            )
        }
        return CalendarSnapshot(provider: Self.provider, sources: selected, window: window, events: events)
    }

    /// Stable across edits and devices; recurring occurrences share an identifier, so the
    /// occurrence date is part of the identity.
    static func externalID(_ event: EKEvent) -> String {
        let base = event.calendarItemExternalIdentifier ?? event.eventIdentifier ?? UUID().uuidString
        guard event.hasRecurrenceRules, let occurrence = event.occurrenceDate else { return base }
        return base + "|" + ISO8601DateFormatter().string(from: occurrence)
    }

    private static func hex(_ color: CGColor?) -> String {
        guard let c = color?.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil),
              let comps = c.components, comps.count >= 3 else { return "#888888" }
        return String(format: "#%02X%02X%02X", Int(comps[0] * 255), Int(comps[1] * 255), Int(comps[2] * 255))
    }
}
