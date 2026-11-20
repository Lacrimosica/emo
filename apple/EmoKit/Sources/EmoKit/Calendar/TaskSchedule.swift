import Foundation
import SwiftData

/// What the backlog shows about when a task is scheduled.
public enum TaskSchedule {
    /// Task blocks that haven't ended yet, earliest first. Feed to `nextStarts`.
    public static func futureBlocks(from now: Date) -> FetchDescriptor<CalendarEvent> {
        let kind = CalendarEventKind.taskBlock.rawValue
        return FetchDescriptor(
            predicate: #Predicate<CalendarEvent> { $0.kindRaw == kind && $0.end > now },
            sortBy: [SortDescriptor(\.start)]
        )
    }

    /// The start of each task's earliest block in `blocks`. Tasks with no block are absent.
    public static func nextStarts(_ blocks: [CalendarEvent]) -> [UUID: Date] {
        var starts: [UUID: Date] = [:]
        for block in blocks {
            guard let id = block.taskID else { continue }
            starts[id] = min(starts[id] ?? block.start, block.start)
        }
        return starts
    }
}
