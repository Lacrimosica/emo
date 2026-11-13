import EmoKit
import SwiftData
import SwiftUI

/// What the user can do to a task block on the timeline. Shared by the context menu and the editor.
enum TaskBlockAction {
    case completeTask
    case skipToday
    case togglePin
    case removeBlock
}

@MainActor
enum TaskBlockActions {
    /// The task a block belongs to, if it still exists.
    static func task(for block: CalendarEvent, in context: ModelContext) -> TaskItem? {
        guard let id = block.taskID else { return nil }
        return try? Backlog(context: context).task(withID: id)
    }

    static func perform(_ action: TaskBlockAction, on block: CalendarEvent, in context: ModelContext) throws {
        let lifecycle = TaskLifecycle(context: context)
        let engine = CalendarEngine(context: context)
        switch action {
        case .completeTask:
            if let task = task(for: block, in: context) { try lifecycle.complete(task) }
        case .skipToday:
            if let task = task(for: block, in: context) {
                try lifecycle.skip(task, on: LocalDay(block.start))
            }
        case .togglePin:
            try engine.setPinned(block, !block.isLocked)
        case .removeBlock:
            try engine.delete(block)
        }
    }

    /// Context-menu items for a task block. `onEditTask` opens the task editor.
    @ViewBuilder
    static func menu(for block: CalendarEvent, context: ModelContext, onEditTask: @escaping (TaskItem) -> Void) -> some View {
        Button("Complete Task", systemImage: "checkmark.circle") { try? perform(.completeTask, on: block, in: context) }
        Button("Skip for Today", systemImage: "forward") { try? perform(.skipToday, on: block, in: context) }
        Button(block.isLocked ? "Unpin" : "Pin Here", systemImage: block.isLocked ? "pin.slash" : "pin") {
            try? perform(.togglePin, on: block, in: context)
        }
        if let task = task(for: block, in: context) {
            Button("Edit Task…", systemImage: "pencil") { onEditTask(task) }
        }
        Divider()
        Button("Remove Block", systemImage: "trash", role: .destructive) { try? perform(.removeBlock, on: block, in: context) }
    }
}
