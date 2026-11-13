import Foundation
import SwiftData

/// One done session of an ongoing task (ticket 31). Sessions count toward the task's weekly
/// target; the task itself never completes from them.
///
/// CloudKit-compatible (ADR 0001): defaulted scalars, no relationships or unique constraints.
@Model
public final class TaskSession {
    public var id: UUID = UUID()
    public var taskID: UUID?
    /// `LocalDay.key` of the day the session was done.
    public var dayKey: String = ""
    public var hours: Double = 0
    public var completedAt: Date = Date()

    public init(taskID: UUID, day: LocalDay, hours: Double, completedAt: Date) {
        self.taskID = taskID
        self.dayKey = day.key
        self.hours = hours
        self.completedAt = completedAt
    }
}
