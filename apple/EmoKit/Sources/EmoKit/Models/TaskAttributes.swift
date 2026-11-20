import Foundation

/// How draining a task is. Matched against the day's energy (check-in) when planning, and
/// the daily energy budget.
public enum EnergyCost: String, CaseIterable, Codable, Sendable, Identifiable {
    case low, medium, high
    public var id: String { rawValue }

    /// 1…5 scale, to compare with a check-in's energy.
    var level: Int {
        switch self {
        case .low: 1
        case .medium: 3
        case .high: 5
        }
    }
}

/// How much a task should get done first, set by the user. Ranks above deadlines' gentle urgency
/// in planning, and orders the backlog.
public enum TaskPriority: String, CaseIterable, Codable, Sendable, Identifiable {
    case first, normal, later
    public var id: String { rawValue }

    /// Planning score added for this priority.
    var score: Int {
        switch self {
        case .first: 400
        case .normal: 0
        case .later: -150
        }
    }
}

/// A category of task: a key that names one of the user's categories (`CategoryDefinition`).
///
/// The four built-ins keep their original keys, so tasks stored before categories became
/// editable still resolve. Their names are only defaults: the user can rename or retarget them.
public struct TaskCategory: Hashable, Sendable, Identifiable {
    public let key: String
    public var id: String { key }

    public init(key: String) {
        self.key = key
    }

    /// Stored form (the key), kept under the old name so existing code keeps compiling.
    public var rawValue: String { key }

    public static let externalCommitment = TaskCategory(key: "external_commitment")
    public static let selfCare = TaskCategory(key: "self_care")
    public static let personal = TaskCategory(key: "personal")
    public static let leisure = TaskCategory(key: "leisure")

    /// The built-in categories, in the order they're first offered.
    public static let builtIns: [TaskCategory] = [.externalCommitment, .selfCare, .personal, .leisure]

    /// Name and colour a built-in starts with (seeded into the store, then editable).
    public static let builtInDefaults: [String: (name: String, colorHex: String, symbol: String)] = [
        externalCommitment.key: ("External commitment", "#E0523D", "person.2"),
        selfCare.key: ("Self care", "#3FA76B", "heart"),
        personal.key: ("Personal", "#4A7BD0", "house"),
        leisure.key: ("Leisure", "#9B6BCB", "figure.walk"),
    ]

    public var isBuiltIn: Bool { Self.builtInDefaults[key] != nil }

    /// Name for a key the user hasn't customised: the built-in name, else the key itself.
    public var defaultName: String { Self.builtInDefaults[key]?.name ?? key }
}

public enum Recurrence: String, CaseIterable, Codable, Sendable, Identifiable {
    case none, daily, weekly
    public var id: String { rawValue }
}
