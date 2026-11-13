import Foundation
import SwiftData

/// Works out how an external calendar must change to mirror Emo's planned blocks.
///
/// The engine owns the decision; an adapter (e.g. `AppleCalendarWriter`) only applies the
/// resulting operations and reports the external IDs of what it created.
@MainActor
public struct CalendarWriteBack {
    public static let provider = "apple-calendar-writeback"

    /// One block as it should appear outside Emo.
    public struct OutboundEvent: Equatable, Sendable {
        public var eventID: UUID
        public var title: String
        public var start: Date
        public var end: Date

        var contentHash: String {
            [title, String(start.timeIntervalSinceReferenceDate), String(end.timeIntervalSinceReferenceDate)].joined(separator: "\u{1F}")
        }
    }

    public enum Operation: Equatable, Sendable {
        case create(OutboundEvent)
        case update(externalID: String, OutboundEvent)
        case delete(externalID: String)
    }

    private let context: ModelContext
    private let calendar: Calendar

    public init(context: ModelContext, calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
    }

    /// The blocks that should be mirrored: task blocks (and their transit) from `from` for `days`.
    public func desiredEvents(from day: LocalDay, days: Int = 14, includeTransit: Bool = true) throws -> [OutboundEvent] {
        let last = day.adding(days: days - 1, calendar: calendar)
        let events = try context.fetch(CalendarEngine.descriptor(from: day, through: last, calendar: calendar))
        return events
            .filter { $0.kind == .taskBlock || (includeTransit && $0.kind == .transit && $0.taskID != nil) }
            .map { OutboundEvent(eventID: $0.id, title: $0.title, start: $0.start, end: $0.end) }
    }

    /// Operations that turn the external calendar's last-written state into `desired`.
    /// Links outside the window (past blocks) are left as they are.
    public func operations(desired: [OutboundEvent], window: DateInterval) throws -> [Operation] {
        let links = try links()
        var linkByEvent: [UUID: ExternalLink] = [:]
        for link in links { if let id = link.eventID { linkByEvent[id] = link } }

        var ops: [Operation] = []
        let desiredIDs = Set(desired.map(\.eventID))
        for event in desired {
            if let link = linkByEvent[event.eventID] {
                if link.contentHash != event.contentHash { ops.append(.update(externalID: link.externalID, event)) }
            } else {
                ops.append(.create(event))
            }
        }
        for link in links {
            guard let id = link.eventID, !desiredIDs.contains(id) else { continue }
            // Keep history: only retract blocks that are gone and weren't already in the past.
            if let blockEnd = Self.endDate(of: link), blockEnd <= window.start { continue }
            ops.append(.delete(externalID: link.externalID))
        }
        return ops
    }

    /// Records what the adapter did, so the next run diffs against it.
    public func record(_ op: Operation, externalID: String?, now: Date = Date()) throws {
        switch op {
        case .create(let event):
            guard let externalID else { return }
            let link = ExternalLink(provider: Self.provider, externalID: externalID, sourceID: "",
                                    contentHash: event.contentHash, now: now)
            link.eventID = event.eventID
            link.sourceID = String(event.end.timeIntervalSinceReferenceDate)   // block end, for history checks
            context.insert(link)
        case .update(let id, let event):
            for link in try links() where link.externalID == id {
                link.contentHash = event.contentHash
                link.sourceID = String(event.end.timeIntervalSinceReferenceDate)
                link.lastSeenAt = now
            }
        case .delete(let id):
            for link in try links() where link.externalID == id { context.delete(link) }
        }
        try context.save()
    }

    /// Forgets everything written (after the external events were removed).
    public func forgetAll() throws {
        for link in try links() { context.delete(link) }
        try context.save()
    }

    public func writtenExternalIDs() throws -> [String] {
        try links().map(\.externalID)
    }

    private func links() throws -> [ExternalLink] {
        let provider = Self.provider
        return try context.fetch(FetchDescriptor<ExternalLink>(predicate: #Predicate { $0.provider == provider }))
    }

    private static func endDate(of link: ExternalLink) -> Date? {
        Double(link.sourceID).map(Date.init(timeIntervalSinceReferenceDate:))
    }
}
