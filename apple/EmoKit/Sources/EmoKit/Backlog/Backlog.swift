import Foundation
import SwiftData

/// What the user fills in when creating a task. Validated before anything is persisted.
public struct TaskDraft: Equatable, Sendable {
    public var name: String
    public var estimatedHours: Double
    public var energyCost: EnergyCost
    public var category: TaskCategory
    public var deadline: Date?

    public init(
        name: String = "",
        estimatedHours: Double = 1,
        energyCost: EnergyCost = .medium,
        category: TaskCategory = .personal,
        deadline: Date? = nil
    ) {
        self.name = name
        self.estimatedHours = estimatedHours
        self.energyCost = energyCost
        self.category = category
        self.deadline = deadline
    }

    public enum ValidationError: Error, Equatable {
        case emptyName
        case nonPositiveEstimate
    }

    public var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    public func validate() throws(ValidationError) {
        if trimmedName.isEmpty { throw .emptyName }
        if !(estimatedHours > 0) { throw .nonPositiveEstimate }
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
            deadline: draft.deadline,
            createdAt: now
        )
        context.insert(task)
        try context.save()
        return task
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
