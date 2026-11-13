import Foundation
import SwiftData

/// The only writer of Emo's internal calendar. Views, the scheduler and (later) the integration
/// reconciler all change events through here, so invariants live in one place.
@MainActor
public struct CalendarEngine {
    /// Shortest event the engine accepts.
    public nonisolated static let minimumDuration: TimeInterval = 5 * 60

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
        descriptor(from: day, through: day, calendar: calendar)
    }

    /// Events overlapping any of the days `first`…`last` (inclusive), earliest first.
    public static func descriptor(from first: LocalDay, through last: LocalDay, calendar: Calendar = .current) -> FetchDescriptor<CalendarEvent> {
        let rangeStart = first.start(in: calendar)
        let rangeEnd = last.end(in: calendar)
        return FetchDescriptor(
            predicate: #Predicate { $0.start < rangeEnd && $0.end > rangeStart },
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

        // Moving or resizing a planned block by hand says "this is when I'll do it": pin it so
        // re-planning leaves it alone.
        if event.isPlannedBlock, newStart != event.start || newEnd != event.end {
            event.isLocked = true
        }
        event.title = newTitle
        if let notes { event.notes = notes }
        event.start = newStart
        event.end = newEnd
        event.updatedAt = now
        try context.save()
    }

    /// Pins (locks) or unpins a task block. Pinned blocks survive re-planning.
    public func setPinned(_ event: CalendarEvent, _ pinned: Bool, now: Date = Date()) throws {
        guard event.isUserEditable else { throw EditError.notUserEditable }
        event.isLocked = pinned
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

    // MARK: Planning

    /// Planned blocks (task blocks and their transit) on `day` that automatic planning may replace:
    /// unlocked, Emo-owned, starting at or after `from`. Past blocks are history; locked blocks are
    /// the user's; manual transit (no task) is never replaced.
    public func replaceableTaskBlocks(on day: LocalDay, from: Date, calendar: Calendar = .current) throws -> [CalendarEvent] {
        try events(on: day, calendar: calendar).filter {
            $0.isPlannedBlock && $0.origin == .local && !$0.isLocked
                && $0.start >= from && $0.start < day.end(in: calendar)
        }
    }

    /// Swaps the day's replaceable task blocks for freshly planned ones, in a single save.
    public func replacePlannedTaskBlocks(
        on day: LocalDay,
        from: Date,
        with blocks: [(task: TaskItem, start: Date, end: Date, kind: CalendarEventKind)],
        calendar: Calendar = .current,
        now: Date = Date()
    ) throws {
        for old in try replaceableTaskBlocks(on: day, from: from, calendar: calendar) {
            context.delete(old)
        }
        for block in blocks {
            precondition(block.kind == .taskBlock || block.kind == .transit, "planning only writes task blocks and transit")
            try Self.validate(start: block.start, end: block.end)
            context.insert(CalendarEvent(
                title: Self.title(for: block.kind, task: block.task),
                start: block.start,
                end: block.end,
                kind: block.kind,
                taskID: block.task.id,
                now: now
            ))
        }
        try context.save()
    }

    static func title(for kind: CalendarEventKind, task: TaskItem) -> String {
        kind == .transit ? "Transit → \(task.name)" : task.name
    }

    /// A standalone transit block the user adds by hand (not tied to a task, never re-planned).
    @discardableResult
    public func createTransit(start: Date, duration: TimeInterval, note: String = "", now: Date = Date()) throws -> CalendarEvent {
        let end = start.addingTimeInterval(duration)
        try Self.validate(start: start, end: end)
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let event = CalendarEvent(title: trimmed.isEmpty ? "Transit" : trimmed, start: start, end: end, kind: .transit, now: now)
        context.insert(event)
        try context.save()
        return event
    }

    // MARK: Task blocks

    /// Every event belonging to a task (task blocks and, later, transit), earliest first.
    public func events(forTask taskID: UUID) throws -> [CalendarEvent] {
        let id: UUID? = taskID
        return try context.fetch(FetchDescriptor<CalendarEvent>(
            predicate: #Predicate { $0.taskID == id },
            sortBy: [SortDescriptor(\.start)]
        ))
    }

    /// Places a pinned block for `task` at a time the user chose.
    @discardableResult
    public func pinTaskBlock(_ task: TaskItem, start: Date, end: Date, now: Date = Date()) throws -> CalendarEvent {
        try Self.validate(start: start, end: end)
        let event = CalendarEvent(title: task.name, start: start, end: end, kind: .taskBlock,
                                  isLocked: true, taskID: task.id, now: now)
        context.insert(event)
        try context.save()
        return event
    }

    /// Removes a task's events that haven't started by `now`, and cuts one in progress short at
    /// `now` (or removes it, if what's left would be under the minimum). Returns the local days
    /// whose plan changed. Past events stay as history.
    @discardableResult
    public func clearFutureEvents(
        forTask taskID: UUID,
        now: Date,
        onlyOn day: LocalDay? = nil,
        includingPinned: Bool = true,
        calendar: Calendar = .current
    ) throws -> Set<LocalDay> {
        var changed: Set<LocalDay> = []
        for event in try events(forTask: taskID) where event.end > now {
            // The part of the event that's still ahead starts on this day.
            let remainingDay = LocalDay(max(event.start, now), calendar: calendar)
            if let day, remainingDay != day { continue }
            if !includingPinned, event.isLocked { continue }
            changed.insert(remainingDay)
            if event.start < now, now.timeIntervalSince(event.start) >= Self.minimumDuration {
                event.end = now
                event.updatedAt = now
            } else {
                context.delete(event)
            }
        }
        try context.save()
        return changed
    }

    /// Removes every event of a task, past ones included (used when the task itself is deleted).
    /// Returns the local days of the events that hadn't ended yet.
    @discardableResult
    public func deleteAllEvents(forTask taskID: UUID, now: Date, calendar: Calendar = .current) throws -> Set<LocalDay> {
        var changed: Set<LocalDay> = []
        for event in try events(forTask: taskID) {
            if event.end > now { changed.insert(LocalDay(max(event.start, now), calendar: calendar)) }
            context.delete(event)
        }
        try context.save()
        return changed
    }

    /// Keeps task-block and transit titles in step with the task's name.
    public func renameEvents(forTask task: TaskItem) throws {
        for event in try events(forTask: task.id) where event.isPlannedBlock {
            let title = Self.title(for: event.kind, task: task)
            if event.title != title { event.title = title }
        }
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
