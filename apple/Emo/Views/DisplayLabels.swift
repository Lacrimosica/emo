import EmoKit
import SwiftUI

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
