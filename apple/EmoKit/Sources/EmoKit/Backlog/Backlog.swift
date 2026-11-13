import Foundation
import SwiftData

/// What the user fills in when creating a task. Validated before anything is persisted.
public struct TaskDraft: Equatable, Sendable {
    public var name: String
    public var estimatedHours: Double
    public var energyCost: EnergyCost
    public var category: TaskCategory
    public var deadline: Date?
    public var recurrence: Recurrence
    public var requiresTransit: Bool
    public var transitMinutes: Int

    public init(
        name: String = "",
        estimatedHours: Double = 1,
        energyCost: EnergyCost = .medium,
        category: TaskCategory = .personal,
        deadline: Date? = nil,
        recurrence: Recurrence = .none,
        requiresTransit: Bool = false,
        transitMinutes: Int = 0
    ) {
        self.name = name
        self.estimatedHours = estimatedHours
        self.energyCost = energyCost
        self.category = category
        self.deadline = deadline
        self.recurrence = recurrence
        self.requiresTransit = requiresTransit
        self.transitMinutes = transitMinutes
    }

    /// A draft pre-filled from an existing task, for editing.
    public init(_ task: TaskItem) {
        self.init(name: task.name, estimatedHours: task.estimatedHours, energyCost: task.energyCost,
                  category: task.category, deadline: task.deadline, recurrence: task.recurrence,
                  requiresTransit: task.requiresTransit, transitMinutes: task.transitMinutes)
    }

    public enum ValidationError: Error, Equatable {
        case emptyName
        case nonPositiveEstimate
        case invalidTransit
    }

    public var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    public func validate() throws(ValidationError) {
        if trimmedName.isEmpty { throw .emptyName }
        if !(estimatedHours > 0) { throw .nonPositiveEstimate }
        if requiresTransit, !(5...480).contains(transitMinutes) { throw .invalidTransit }
    }

    public var isValid: Bool { (try? validate()) != nil }
}

/// The set of open (not completed) tasks. Views go through this, never the store directly.
@MainActor
public struct Backlog {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    @discardableResult
    public func add(_ draft: TaskDraft, now: Date = Date()) throws -> TaskItem {
        try draft.validate()
        let task = TaskItem(
            name: draft.trimmedName,
            estimatedHours: draft.estimatedHours,
            energyCost: draft.energyCost,
            category: draft.category,
            recurrence: draft.recurrence,
            deadline: draft.deadline,
            requiresTransit: draft.requiresTransit,
            transitMinutes: draft.requiresTransit ? draft.transitMinutes : 0,
            createdAt: now
        )
        context.insert(task)
        try context.save()
        return task
    }

    public func task(withID id: UUID) throws -> TaskItem? {
        var descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Open tasks, newest first.
    public func openTasks() throws -> [TaskItem] {
        try context.fetch(Self.openTasksDescriptor)
    }

    /// Shared with SwiftUI's `@Query` so the list and the domain agree on what "backlog" means.
    public static var openTasksDescriptor: FetchDescriptor<TaskItem> {
        FetchDescriptor(
            predicate: #Predicate { $0.completedAt == nil },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
    }
}
