import Foundation

/// One event as an integration reports it. Integrations deal only in these; they never touch the
/// internal calendar.
public struct ExternalEvent: Equatable, Sendable {
    public var externalID: String
    public var sourceID: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var notes: String

    public init(externalID: String, sourceID: String, title: String, start: Date, end: Date, isAllDay: Bool = false, notes: String = "") {
        self.externalID = externalID
        self.sourceID = sourceID
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.notes = notes
    }

    var contentHash: String {
        [title, String(start.timeIntervalSinceReferenceDate), String(end.timeIntervalSinceReferenceDate),
         isAllDay ? "1" : "0", notes].joined(separator: "\u{1F}")
    }
}

/// Everything an integration currently has in `sources` within `window`. The reconciler diffs it
/// against what it saw last time, so adapters don't need to track changes themselves.
public struct CalendarSnapshot: Sendable {
    public var provider: String
    public var sources: Set<String>
    public var window: DateInterval
    public var events: [ExternalEvent]

    public init(provider: String, sources: Set<String>, window: DateInterval, events: [ExternalEvent]) {
        self.provider = provider
        self.sources = sources
        self.window = window
        self.events = events
    }
}
