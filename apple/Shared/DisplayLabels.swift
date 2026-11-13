import EmoKit
import SwiftUI

/// What this platform calls Apple's Calendar app, for settings copy.
enum PlatformNames {
    #if os(macOS)
    static let calendarApp = "Calendar.app"
    #else
    static let calendarApp = "the Calendar app"
    #endif
}

extension EnergyCost {
    var label: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }

    var tint: Color {
        switch self {
        case .low: .green
        case .medium: .orange
        case .high: .red
        }
    }
}

extension CalendarEventKind {
    var tint: Color {
        switch self {
        case .fixed: .blue
        case .taskBlock: .purple
        case .transit: .orange
        case .buffer: .gray
        }
    }
}

extension TaskCategory {
    var label: String {
        switch self {
        case .externalCommitment: "External commitment"
        case .selfCare: "Self care"
        case .personal: "Personal"
        case .leisure: "Leisure"
        }
    }
}

extension Double {
    /// 1.5 → "1h 30m", 0.75 → "45m", 2 → "2h".
    var hoursLabel: String {
        let totalMinutes = Int((self * 60).rounded())
        let h = totalMinutes / 60, m = totalMinutes % 60
        switch (h, m) {
        case (0, _): return "\(m)m"
        case (_, 0): return "\(h)h"
        default: return "\(h)h \(m)m"
        }
    }
}

extension Recurrence {
    var label: String {
        switch self {
        case .none: "Never"
        case .daily: "Daily"
        case .weekly: "Weekly"
        }
    }
}

extension ListRole {
    var label: String {
        switch self {
        case .inbox: "Inbox"
        case .routine: "Daily checklist"
        case .nextAction: "Next action"
        case .waiting: "Waiting"
        case .project: "Projects"
        case .someday: "Someday / Maybe"
        case .shopping: "Shopping"
        case .idea: "Ideas"
        }
    }

    var systemImage: String {
        switch self {
        case .inbox: "tray"
        case .routine: "checklist"
        case .nextAction: "arrow.right.circle"
        case .waiting: "hourglass"
        case .project: "folder"
        case .someday: "moon.zzz"
        case .shopping: "cart"
        case .idea: "lightbulb"
        }
    }

    /// What Emo does with tasks from such a list, for Settings.
    var schedulingNote: String { isSchedulable ? "Scheduled" : "Kept, not scheduled" }
}

struct EnergyBadge: View {
    let cost: EnergyCost

    var body: some View {
        Text(cost.label)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(cost.tint.opacity(0.18), in: Capsule())
            .foregroundStyle(cost.tint)
    }
}

/// "↻ 2 of 3 this week · 1h" for an ongoing task.
struct OngoingProgressLabel: View {
    let task: TaskItem
    let doneThisWeek: Int

    var body: some View {
        Label("\(doneThisWeek) of \(task.sessionsPerWeek) this week · \(task.sessionHours.hoursLabel)",
              systemImage: "arrow.trianglehead.2.clockwise")
            .foregroundStyle(doneThisWeek >= task.sessionsPerWeek ? Color.green : Color.secondary)
            .accessibilityLabel("Ongoing: \(doneThisWeek) of \(task.sessionsPerWeek) sessions done this week, \(task.sessionHours.hoursLabel) each")
    }
}
