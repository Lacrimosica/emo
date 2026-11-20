import EmoKit
import Foundation
import SwiftData

/// Today-screen logic shared by the Mac and iPhone apps: what Plan Day reports, pinned-block
/// conflicts, and where a new event starts.
@MainActor
enum DayScreen {
    /// Plan Day: fills the day's free time from the backlog and returns what happened. Without a
    /// check-in it plans with the default energy and says so, rather than asking first.
    static func plan(_ day: LocalDay, hasCheckIn: Bool, context: ModelContext) -> String {
        do {
            if try Backlog(context: context).openTasks().isEmpty {
                return "Your backlog is empty. Add some tasks, then plan."
            }
            let summary = try DayPlanning(context: context).plan(day)
            return describe(summary, assumedEnergy: !hasCheckIn)
        } catch {
            return "Couldn't plan the day: \(error.localizedDescription)"
        }
    }

    /// Plan Week: fills the rest of the week (from today, or the week's first day if later) and
    /// says what happened.
    static func planWeek(starting weekStart: LocalDay, today: LocalDay, context: ModelContext) -> String {
        let last = weekStart.adding(days: 6)
        guard last >= today else { return "This week is over." }
        do {
            if try Backlog(context: context).openTasks().isEmpty {
                return "Your backlog is empty. Add some tasks, then plan."
            }
            let summary = try DayPlanning(context: context).plan(from: max(weekStart, today), through: last)
            var message = summary.planned > 0
                ? "Planned \((summary.planned / 3600).hoursLabel) this week."
                : "Nothing more fits this week."
            if !summary.unplacedTaskNames.isEmpty {
                let named = summary.unplacedTaskNames.prefix(3).map { "“\($0)”" }
                let rest = summary.unplacedTaskNames.count - named.count
                message += " No room for \(named.formatted(.list(type: .and)))\(rest > 0 ? " and \(rest) more" : "")."
            }
            return message
        } catch {
            return "Couldn't plan the week: \(error.localizedDescription)"
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
            let named = s.unplacedTaskNames.prefix(3).map { "“\($0)”" }
            let rest = s.unplacedTaskCount - named.count
            var list = named.formatted(.list(type: .and))
            if rest > 0 { list += " and \(rest) more" }
            parts.append("Not placed in the next two days: \(list.isEmpty ? "\(s.unplacedTaskCount) tasks" : list).")
        }
        if !s.unmetTodayGoals.isEmpty {
            let names = s.unmetTodayGoals.map { "“\($0)”" }.formatted(.list(type: .and))
            parts.append("\(names) \(s.unmetTodayGoals.count == 1 ? "is" : "are") marked for today but didn't fit.")
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
