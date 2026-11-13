import EmoKit
import Foundation
import SwiftData

/// Today-screen logic shared by the Mac and iPhone apps: what Plan Day reports, pinned-block
/// conflicts, and where a new event starts.
@MainActor
enum DayScreen {
    enum PlanOutcome: Equatable {
        /// Today's plan is sized by today's energy, so the user checks in first; plan again once saved.
        case needsCheckIn
        case message(String)
    }

    /// Plan Day: fills the day's free time from the backlog and says what happened.
    static func plan(_ day: LocalDay, today: LocalDay, hasCheckIn: Bool, context: ModelContext) -> PlanOutcome {
        if day == today, !hasCheckIn { return .needsCheckIn }
        do {
            if try Backlog(context: context).openTasks().isEmpty {
                return .message("Your backlog is empty. Add some tasks, then plan.")
            }
            let summary = try DayPlanning(context: context).plan(day)
            return .message(describe(summary, assumedEnergy: !hasCheckIn))
        } catch {
            return .message("Couldn't plan the day: \(error.localizedDescription)")
        }
    }

    /// Unschedule All: removes every upcoming task block and says how many went.
    static func unscheduleAll(context: ModelContext) -> String {
        do {
            let count = try CalendarEngine(context: context).clearAllFuturePlannedBlocks(now: .now)
            return count == 0 ? "Nothing was scheduled." : "Unscheduled \(count) block\(count == 1 ? "" : "s")."
        } catch {
            return "Couldn't unschedule: \(error.localizedDescription)"
        }
    }

    /// The message shown after Plan Day.
    static func describe(_ s: DayPlanning.Summary, assumedEnergy: Bool) -> String {
        var parts: [String] = []
        if s.planned.planned == 0, s.spill.planned == 0, s.unplacedTaskCount == 0 {
            parts.append("Everything in your backlog is already planned.")
        } else if s.planned.planned > 0 {
            parts.append("Planned \((s.planned.planned / 3600).hoursLabel) across \(s.planned.taskCount) task\(s.planned.taskCount == 1 ? "" : "s").")
        } else {
            parts.append(s.planned.day == LocalDay.today() ? "Nothing more fits today." : "Nothing fits on this day.")
        }
        if s.spill.planned > 0 {
            parts.append("\((s.spill.planned / 3600).hoursLabel) moved to \(s.spill.day.start().formatted(.dateTime.weekday(.wide))).")
        }
        if s.unplacedTaskCount > 0 {
            parts.append("\(s.unplacedTaskCount) task\(s.unplacedTaskCount == 1 ? "" : "s") still in the backlog.")
        }
        if assumedEnergy { parts.append("No check-in for this day, so medium energy was assumed.") }
        return parts.joined(separator: " ")
    }

    /// Pinned task blocks that collide with a timed calendar event (pinned blocks are never moved
    /// automatically, so the user decides).
    static func pinnedConflictCount(in dayEvents: [CalendarEvent]) -> Int {
        let busy = dayEvents.filter { $0.origin == .linked && !$0.isAllDay }
        return dayEvents.filter { block in
            block.kind == .taskBlock && block.isLocked && busy.contains { $0.start < block.end && block.start < $0.end }
        }.count
    }

    static func pinnedConflictMessage(count: Int) -> String {
        "\(count) pinned block\(count == 1 ? "" : "s") overlap\(count == 1 ? "s" : "") a calendar event. Move or unpin \(count == 1 ? "it" : "them") if needed."
    }

    /// Where a new one-hour event starts: the next quarter hour today, or 9:00 on other days.
    static func newEventStart(on day: LocalDay, today: LocalDay, calendar: Calendar = .current) -> Date {
        if day == today {
            let next = Date.now.addingTimeInterval(7.5 * 60).snapped(toMinutes: 15, calendar: calendar)
            return min(next, day.end(in: calendar).addingTimeInterval(-3600))
        }
        return calendar.date(byAdding: .hour, value: 9, to: day.start(in: calendar))!
    }
}
