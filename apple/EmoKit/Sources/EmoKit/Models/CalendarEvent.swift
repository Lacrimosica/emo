import Foundation
import SwiftData

/// What an internal calendar event represents.
public enum CalendarEventKind: String, CaseIterable, Codable, Sendable {
    /// A commitment at a set time (meeting, appointment). The scheduler plans around it.
    case fixed
    /// Time the scheduler (or the user) allocated to a task.
    case taskBlock
    /// Travel time before a task.
    case transit
    /// Deliberately unplanned breathing room.
    case buffer
}

/// Where an internal event came from.
public enum CalendarEventOrigin: String, CaseIterable, Codable, Sendable {
    /// Created in Emo; Emo owns it.
    case local
    /// Mirrors an item from an integration (Apple Calendar, Reminders…). Only the engine's
    /// reconciler may change it, in response to the integration's change set (ticket 09).
    case linked
}

/// An event on Emo's internal calendar — the source of truth the scheduler and views work from.
///
/// Legacy alias: `schedule_block` (with `type = fixed_event | task | transit | buffer`).
/// CloudKit-compatible (ADR 0001). Write only through `CalendarEngine`.
@Model
public final class CalendarEvent {
    public var id: UUID = UUID()
    public var title: String = ""
    public var notes: String = ""
    public var start: Date = Date()
    public var end: Date = Date()
    public var kindRaw: String = CalendarEventKind.fixed.rawValue
    public var originRaw: String = CalendarEventOrigin.local.rawValue
    /// Locked events are never moved or removed by automatic (re)planning.
    public var isLocked: Bool = false
    /// The task this event is for, when `kind` is `.taskBlock` or `.transit`.
    public var taskID: UUID?
    /// All-day events are shown, but don't take up plannable time.
    public var isAllDay: Bool = false
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    init(
        title: String,
        start: Date,
        end: Date,
        kind: CalendarEventKind,
        origin: CalendarEventOrigin = .local,
        isLocked: Bool = false,
        taskID: UUID? = nil,
        notes: String = "",
        now: Date = Date()
    ) {
        self.title = title
        self.start = start
        self.end = end
        self.kindRaw = kind.rawValue
        self.originRaw = origin.rawValue
        self.isLocked = isLocked
        self.taskID = taskID
        self.notes = notes
        self.createdAt = now
        self.updatedAt = now
    }

    public var kind: CalendarEventKind {
        CalendarEventKind(rawValue: kindRaw) ?? .fixed
    }

    public var origin: CalendarEventOrigin {
        CalendarEventOrigin(rawValue: originRaw) ?? .local
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }

    /// A block that planning manages for a task: a task block, or the transit leading to one.
    public var isPlannedBlock: Bool {
        kind == .taskBlock || (kind == .transit && taskID != nil)
    }

    /// Whether the user may edit this event directly.
    public var isUserEditable: Bool { origin == .local }
}
