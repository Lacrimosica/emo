import Foundation
import SwiftData

/// Routine lists ("CHECKLIST DAILY") as one daily block (ticket 34).
///
/// Each routine list area gets an Emo-managed checklist task: ongoing, every day, as long as its
/// open items together. The items themselves are never planned. Ticking an item marks it done for
/// that day (a `TaskSession`); once every item is done, the checklist's session for the day is
/// logged and its block goes. Items are daily whether or not they repeat in Reminders.
@MainActor
public struct RoutineChecklist {
    public static let defaultName = "Daily checklist"

    private let context: ModelContext
    private let calendar: Calendar

    public init(context: ModelContext, calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
    }

    private var lifecycle: TaskLifecycle { TaskLifecycle(context: context, calendar: calendar) }

    /// The checklist's name for a list area.
    public static func name(forArea area: String?) -> String {
        guard let area = area?.trimmingCharacters(in: .whitespaces), !area.isEmpty else { return defaultName }
        return "Checklist: \(area)"
    }

    /// Creates, resizes and removes checklist tasks to match the open routine items.
    public func sync(now: Date = Date()) throws {
        let open = try Backlog(context: context).openTasks()
        let items = Dictionary(grouping: open.filter(\.isRoutineItem), by: { Self.key($0.listArea) })
        var checklists: [String: TaskItem] = [:]
        for checklist in open where checklist.isChecklist {
            let key = Self.key(checklist.listArea)
            if checklists[key] == nil, items[key] != nil { checklists[key] = checklist } else { try lifecycle.delete(checklist, now: now) }
        }

        for (key, group) in items {
            let hours = Self.sessionHours(for: group)
            let area = group.first?.listArea
            if let checklist = checklists[key] {
                if checklist.sessionHours != hours {
                    var draft = TaskDraft(checklist)
                    draft.estimatedHours = hours
                    draft.sessionHours = hours
                    try lifecycle.update(checklist, with: draft, now: now)
                }
                if checklist.name != Self.name(forArea: area) { checklist.name = Self.name(forArea: area) }
            } else {
                var draft = TaskDraft(name: Self.name(forArea: area), estimatedHours: hours, energyCost: .low, category: .selfCare)
                draft.isOngoing = true
                draft.sessionsPerWeek = 7
                draft.sessionHours = hours
                let checklist = try Backlog(context: context).add(draft, now: now)
                checklist.isChecklist = true
                checklist.listRole = .routine
                checklist.listArea = area
            }
        }
        try context.save()
    }

    /// Marks a routine item done on `day` (again is a no-op). When that completes the day's
    /// checklist, the checklist's session is logged too.
    public func markDone(_ item: TaskItem, on day: LocalDay, now: Date = Date()) throws {
        guard item.isRoutineItem, try !isDone(item, on: day) else { return }
        context.insert(TaskSession(taskID: item.id, day: day, hours: item.estimatedHours, completedAt: now))
        try context.save()

        guard let checklist = try checklist(for: item), try !isDone(checklist, on: day) else { return }
        let siblings = try items(of: checklist)
        if try siblings.allSatisfy({ try isDone($0, on: day) }) {
            try lifecycle.logSession(checklist, on: day, now: now)
        }
    }

    /// Whether a routine item (or a checklist) is done on `day`.
    public func isDone(_ task: TaskItem, on day: LocalDay) throws -> Bool {
        let id = task.id, key = day.key
        return try context.fetchCount(FetchDescriptor<TaskSession>(predicate: #Predicate { $0.taskID == id && $0.dayKey == key })) > 0
    }

    /// The open items a checklist stands for.
    public func items(of checklist: TaskItem) throws -> [TaskItem] {
        let key = Self.key(checklist.listArea)
        return try Backlog(context: context).openTasks().filter { $0.isRoutineItem && Self.key($0.listArea) == key }
    }

    public func checklist(for item: TaskItem) throws -> TaskItem? {
        let key = Self.key(item.listArea)
        return try Backlog(context: context).openTasks().first { $0.isChecklist && Self.key($0.listArea) == key }
    }

    /// The items' estimates together, rounded up to 5 minutes.
    static func sessionHours(for items: [TaskItem]) -> Double {
        let minutes = items.reduce(0) { $0 + $1.estimatedHours * 60 }
        return max((minutes / 5).rounded(.up) * 5, 5) / 60
    }

    private static func key(_ area: String?) -> String {
        area?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
    }
}
