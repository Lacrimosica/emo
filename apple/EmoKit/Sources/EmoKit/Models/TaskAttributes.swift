import Foundation

/// How draining a task is. Drives scheduling priority and the daily energy budget.
public enum EnergyCost: String, CaseIterable, Codable, Sendable, Identifiable {
    case low, medium, high
    public var id: String { rawValue }
}

public enum TaskCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    case externalCommitment = "external_commitment"
    case selfCare = "self_care"
    case personal
    case leisure
    public var id: String { rawValue }
}

public enum Recurrence: String, CaseIterable, Codable, Sendable, Identifiable {
    case none, daily, weekly
    public var id: String { rawValue }
}
