import EmoKit
import SwiftData
import SwiftUI

extension TaskPriority {
    var label: String {
        switch self {
        case .first: "Do first"
        case .normal: "Normal"
        case .later: "Later"
        }
    }
}

/// A category as a coloured chip, named by the user's category list.
struct CategoryChip: View {
    let key: String
    let categories: [CategoryDefinition]

    var body: some View {
        let stored = categories.first { $0.key == key }
        let fallback = TaskCategory.builtInDefaults[key]
        let name = stored?.name ?? TaskCategory(key: key).defaultName
        let tint = Color(hex: stored?.colorHex ?? fallback?.colorHex ?? "#888888")
        Label(name, systemImage: stored?.symbol ?? fallback?.symbol ?? "tag")
            .font(.caption.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
    }
}

/// "Do first" or "Later". Normal priority shows nothing.
struct PriorityTag: View {
    let priority: TaskPriority

    var body: some View {
        switch priority {
        case .normal:
            EmptyView()
        case .first:
            Label(priority.label, systemImage: "arrow.up.circle.fill").foregroundStyle(.orange)
        case .later:
            Label(priority.label, systemImage: "arrow.down.circle").foregroundStyle(.secondary)
        }
    }
}

/// When a task is next scheduled, or that it isn't.
struct ScheduleLabel: View {
    let start: Date?

    var body: some View {
        if let start {
            Label(Self.text(for: start), systemImage: "calendar.badge.clock")
        } else {
            Label("Not scheduled", systemImage: "calendar.badge.exclamationmark")
                .foregroundStyle(.orange)
        }
    }

    /// "Today 10:00", "Tomorrow 09:30", or "Mon 14:00".
    static func text(for start: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let day = LocalDay(start, calendar: calendar)
        let time = start.formatted(date: .omitted, time: .shortened)
        if day == LocalDay(now, calendar: calendar) { return "Today \(time)" }
        if day == LocalDay(now, calendar: calendar).adding(days: 1, calendar: calendar) { return "Tomorrow \(time)" }
        return start.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }
}

/// Changes one thing on a task (priority, category…) through the normal update, so its day is
/// re-planned, while keeping the review flags an imported task still needs.
@MainActor
enum TaskQuickEdit {
    static func apply(_ change: (inout TaskDraft) -> Void, to task: TaskItem, context: ModelContext) throws {
        var draft = TaskDraft(task)
        change(&draft)
        let needsReview = task.needsReview, fromMemory = task.sizedFromMemory
        try TaskLifecycle(context: context).update(task, with: draft)
        task.needsReview = needsReview
        task.sizedFromMemory = fromMemory
        try context.save()
        // A task that just moved up may now fit a planned day it wasn't on.
        try DayPlanning(context: context).refreshPlannedDays()
    }
}
