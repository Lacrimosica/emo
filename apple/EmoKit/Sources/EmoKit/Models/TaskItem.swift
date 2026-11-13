import Foundation
import SwiftData

/// A unit of work the user wants done. Lives in the backlog until scheduled or completed.
///
/// Named `TaskItem` (not `Task`) to avoid clashing with Swift concurrency's `Task`.
///
/// CloudKit-compatible by construction (see docs/adr/0001-local-first-swiftdata-store.md):
/// every stored property is optional or defaulted, there are no unique constraints,
/// and enums are stored as raw strings behind typed accessors.
@Model
public final class TaskItem {
    public var id: UUID = UUID()
    public var name: String = ""
    public var estimatedHours: Double = 1
    public var energyCostRaw: String = EnergyCost.medium.rawValue
    public var categoryRaw: String = TaskCategory.personal.rawValue
    public var recurrenceRaw: String = Recurrence.none.rawValue
    public var deadline: Date?
    public var requiresTransit: Bool = false
    public var transitMinutes: Int = 0
    public var createdAt: Date = Date()
    public var completedAt: Date?

    public init(
        name: String,
        estimatedHours: Double,
        energyCost: EnergyCost,
        category: TaskCategory,
        recurrence: Recurrence = .none,
        deadline: Date? = nil,
        requiresTransit: Bool = false,
        transitMinutes: Int = 0,
        createdAt: Date = Date()
    ) {
        self.name = name
        self.estimatedHours = estimatedHours
        self.energyCostRaw = energyCost.rawValue
        self.categoryRaw = category.rawValue
        self.recurrenceRaw = recurrence.rawValue
        self.deadline = deadline
        self.requiresTransit = requiresTransit
        self.transitMinutes = transitMinutes
        self.createdAt = createdAt
    }

    public var energyCost: EnergyCost {
        get { EnergyCost(rawValue: energyCostRaw) ?? .medium }
        set { energyCostRaw = newValue.rawValue }
    }

    public var category: TaskCategory {
        get { TaskCategory(rawValue: categoryRaw) ?? .personal }
        set { categoryRaw = newValue.rawValue }
    }

    public var recurrence: Recurrence {
        get { Recurrence(rawValue: recurrenceRaw) ?? .none }
        set { recurrenceRaw = newValue.rawValue }
    }

    public var isCompleted: Bool { completedAt != nil }
}
