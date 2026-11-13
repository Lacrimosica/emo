import Foundation
import SwiftData

/// The engine side of calendar integrations: turns an integration's snapshot into linked fixed
/// events on the internal calendar, then repairs the plan around them.
///
/// Only this type (through `CalendarEngine`'s linked-event writes) changes linked events.
@MainActor
public struct CalendarReconciler {
    public struct Result: Equatable, Sendable {
        public var added = 0
        public var updated = 0
        public var removed = 0
        /// Days whose plan was re-made because linked events changed under it.
        public var replannedDays: [LocalDay] = []
        /// Pinned task blocks that now overlap a linked event. Left alone; shown to the user.
        public var pinnedConflicts: [UUID] = []

        public var changed: Bool { added + updated + removed > 0 }
    }

    private let context: ModelContext
    private let calendar: Calendar

    public init(context: ModelContext, calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
    }

    private var engine: CalendarEngine { CalendarEngine(context: context) }

    @discardableResult
    public func apply(_ snapshot: CalendarSnapshot, now: Date = Date()) throws -> Result {
        var result = Result()
        var touched: [DateInterval] = []

        var links = try links(for: snapshot.provider)
        // Collapse duplicate links (possible after a sync merge): keep one per external ID.
        var byExternalID: [String: ExternalLink] = [:]
        for link in links {
            if byExternalID[link.externalID] == nil { byExternalID[link.externalID] = link }
            else { try removeLink(link, touched: &touched) }
        }
        links = Array(byExternalID.values)

        var seen: Set<String> = []
        for item in snapshot.events where snapshot.sources.contains(item.sourceID) && item.end > item.start {
            seen.insert(item.externalID)
            if let link = byExternalID[item.externalID], let event = try event(link.eventID) {
                guard link.contentHash != item.contentHash || link.sourceID != item.sourceID else {
                    link.lastSeenAt = now
                    continue
                }
                touched.append(DateInterval(start: event.start, end: event.end))
                engine.updateLinkedEvent(event, title: item.title, start: item.start, end: item.end,
                                         isAllDay: item.isAllDay, notes: item.notes, now: now)
                link.contentHash = item.contentHash
                link.sourceID = item.sourceID
                link.lastSeenAt = now
                result.updated += 1
            } else {
                if let stale = byExternalID[item.externalID] { context.delete(stale) }   // link to a vanished event
                let event = engine.insertLinkedEvent(title: item.title, start: item.start, end: item.end,
                                                     isAllDay: item.isAllDay, notes: item.notes, now: now)
                let link = ExternalLink(provider: snapshot.provider, externalID: item.externalID,
                                        sourceID: item.sourceID, contentHash: item.contentHash, now: now)
                link.eventID = event.id
                context.insert(link)
                result.added += 1
            }
            touched.append(DateInterval(start: item.start, end: item.end))
        }

        // Gone from a covered source within the window → removed upstream.
        for link in links where !seen.contains(link.externalID) && snapshot.sources.contains(link.sourceID) {
            guard let event = try event(link.eventID) else { context.delete(link); continue }
            guard event.end > snapshot.window.start, event.start < snapshot.window.end else { continue }
            try removeLink(link, touched: &touched)
            result.removed += 1
        }
        try context.save()

        try repair(touched, now: now, into: &result)
        return result
    }

    /// Removes everything an integration brought in, except items from `keeping` sources
    /// (used when the integration is turned off, or calendars are deselected).
    @discardableResult
    public func removeAll(provider: String, keeping: Set<String> = [], now: Date = Date()) throws -> Result {
        var result = Result()
        var touched: [DateInterval] = []
        for link in try links(for: provider) where !keeping.contains(link.sourceID) {
            try removeLink(link, touched: &touched)
            result.removed += 1
        }
        try context.save()
        try repair(touched, now: now, into: &result)
        return result
    }

    // MARK: Helpers

    private func links(for provider: String) throws -> [ExternalLink] {
        try context.fetch(FetchDescriptor<ExternalLink>(predicate: #Predicate { $0.provider == provider }))
    }

    private func event(_ id: UUID?) throws -> CalendarEvent? {
        guard let id else { return nil }
        var descriptor = FetchDescriptor<CalendarEvent>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func removeLink(_ link: ExternalLink, touched: inout [DateInterval]) throws {
        if let event = try event(link.eventID) {
            touched.append(DateInterval(start: event.start, end: max(event.end, event.start)))
            engine.deleteLinkedEvent(event)
        }
        context.delete(link)
    }

    /// Re-plans upcoming days the changes touched, but only days that already have a plan
    /// (task blocks) — a day the user never planned stays unplanned. Reports pinned collisions.
    private func repair(_ touched: [DateInterval], now: Date, into result: inout Result) throws {
        let today = LocalDay(now, calendar: calendar)
        var days: Set<LocalDay> = []
        for interval in touched {
            var day = LocalDay(interval.start, calendar: calendar)
            let last = LocalDay(max(interval.start, interval.end.addingTimeInterval(-1)), calendar: calendar)
            while day <= last {
                if day >= today { days.insert(day) }
                day = day.adding(days: 1, calendar: calendar)
            }
        }
        let planning = DayPlanning(context: context, calendar: calendar)
        var coveredThrough: LocalDay?
        for day in days.sorted() {
            let events = try engine.events(on: day, calendar: calendar)
            guard events.contains(where: { $0.kind == .taskBlock }) else { continue }
            if let covered = coveredThrough, day <= covered { continue }
            try planning.plan(day, now: now)
            result.replannedDays.append(day)
            coveredThrough = day.adding(days: 1, calendar: calendar)
        }
        // Pinned blocks overlapping linked busy events, on any touched upcoming day.
        for day in days.sorted() {
            let events = try engine.events(on: day, calendar: calendar)
            let busy = events.filter { $0.origin == .linked && !$0.isAllDay }
            for block in events where block.kind == .taskBlock && block.isLocked
                && busy.contains(where: { $0.start < block.end && block.start < $0.end }) {
                if !result.pinnedConflicts.contains(block.id) { result.pinnedConflicts.append(block.id) }
            }
        }
    }
}
