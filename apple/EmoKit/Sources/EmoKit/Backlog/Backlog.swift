import Foundation
import SwiftData

/// What the user fills in when creating a task. Validated before anything is persisted.
public struct TaskDraft: Equatable, Sendable {
    public var name: String
    public var estimatedHours: Double
    public var energyCost: EnergyCost
    public var category: TaskCategory
    public var priority: TaskPriority = .normal
    public var deadline: Date?
    public var recurrence: Recurrence
    public var requiresTransit: Bool
    public var transitMinutes: Int
    /// Plan as one unbroken block (see `TaskItem.keepTogether`).
    public var keepTogether: Bool = false
    /// Ongoing practice with a weekly target (ticket 31); `estimatedHours` is ignored for these.
    public var isOngoing: Bool = false
    public var sessionsPerWeek: Int = TaskItem.defaultSessionsPerWeek
    public var sessionHours: Double = TaskItem.defaultSessionHours

    public init(
        name: String = "",
        estimatedHours: Double = 1,
        energyCost: EnergyCost = .medium,
        category: TaskCategory = .personal,
        priority: TaskPriority = .normal,
        deadline: Date? = nil,
        recurrence: Recurrence = .none,
        requiresTransit: Bool = false,
        transitMinutes: Int = 0
    ) {
        self.name = name
        self.estimatedHours = estimatedHours
        self.energyCost = energyCost
        self.category = category
        self.priority = priority
        self.deadline = deadline
        self.recurrence = recurrence
        self.requiresTransit = requiresTransit
        self.transitMinutes = transitMinutes
    }

    /// A draft pre-filled from an existing task, for editing.
    public init(_ task: TaskItem) {
        self.init(name: task.name, estimatedHours: task.estimatedHours, energyCost: task.energyCost,
                  category: task.category, priority: task.priority, deadline: task.deadline, recurrence: task.recurrence,
                  requiresTransit: task.requiresTransit, transitMinutes: task.transitMinutes)
        keepTogether = task.keepTogether
        isOngoing = task.isOngoing
        sessionsPerWeek = task.sessionsPerWeek
        sessionHours = task.sessionHours
    }

    /// Copies the ongoing settings onto `task` (an ongoing task has no recurrence, and its
    /// estimate is one session).
    func applyOngoing(to task: TaskItem) {
        task.isOngoing = isOngoing
        guard isOngoing else { return }
        task.sessionsPerWeek = min(max(sessionsPerWeek, 1), 14)
        task.sessionHours = min(max(sessionHours, 0.25), 12)
        task.estimatedHours = task.sessionHours
        task.recurrence = .none
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
            priority: draft.priority,
            recurrence: draft.recurrence,
            deadline: draft.deadline,
            requiresTransit: draft.requiresTransit,
            transitMinutes: draft.requiresTransit ? draft.transitMinutes : 0,
            createdAt: now
        )
        task.keepTogether = draft.keepTogether
        draft.applyOngoing(to: task)
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

    /// The order the backlog shows tasks in, which is the order planning favours them: priority,
    /// then nearest deadline (none last), then oldest first.
    public static func displayOrder(_ tasks: [TaskItem]) -> [TaskItem] {
        tasks.sorted { a, b in
            if a.priority != b.priority { return rank(a.priority) < rank(b.priority) }
            switch (a.deadline, b.deadline) {
            case let (x?, y?) where x != y: return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.createdAt < b.createdAt
            }
        }
    }

    private static func rank(_ priority: TaskPriority) -> Int {
        switch priority {
        case .first: 0
        case .normal: 1
        case .later: 2
        }
    }

    /// Shared with SwiftUI's `@Query` so the list and the domain agree on what "backlog" means.
    public static var openTasksDescriptor: FetchDescriptor<TaskItem> {
        FetchDescriptor(
            predicate: #Predicate { $0.completedAt == nil },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
    }
}
