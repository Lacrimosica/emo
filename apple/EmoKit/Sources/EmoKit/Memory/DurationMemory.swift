import Foundation
import SwiftData

/// One completed task's estimate against the time it actually took (ticket 19).
///
/// "Actual" is the task-block time that had run when the user ticked it done. Emo has no timer,
/// so this mostly catches tasks that finish early; a task only shows as running long when its
/// blocks were stretched by hand.
///
/// CloudKit-compatible (ADR 0001): defaulted scalars, no relationships or unique constraints.
@Model
public final class DurationObservation {
    public var id: UUID = UUID()
    /// Same grouping as time of day: `area:<name>` or `category:<raw>` (`TimeOfDayMemory.group`).
    public var group: String = ""
    public var estimatedHours: Double = 1
    public var actualHours: Double = 1
    public var recordedAt: Date = Date()

    init(group: String, estimatedHours: Double, actualHours: Double, recordedAt: Date) {
        self.group = group
        self.estimatedHours = estimatedHours
        self.actualHours = actualHours
        self.recordedAt = recordedAt
    }
}

/// Learns how far off the user's estimates are per kind of task and gives the planner a
/// correction factor ("admin in Poli takes about 0.7× the estimate"). The task's own estimate is
/// never changed; only how much time the planner reserves for it.
@MainActor
public struct DurationMemory {
    public struct Learned: Equatable, Sendable, Identifiable {
        public var group: String
        public var factor: Double
        /// How many completions it's based on.
        public var observations: Int
        public var id: String { group }

        public var name: String { String(group.split(separator: ":", maxSplits: 1).last ?? "") }
        public var isArea: Bool { group.hasPrefix("area:") }
    }

    public static let capacity = 500
    /// Completions needed before a group gets a factor.
    static let minimumObservations = 3
    /// An observation's weight halves every this many days.
    static let halfLifeDays = 45.0
    static let factorRange = 0.5...2.0
    /// Factors this close to 1 aren't worth correcting for.
    static let deadBand = 0.1
    /// Single completions further off than this are treated as noise (forgot to tick, ticked early).
    static let ratioRange = 0.2...3.0

    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    /// Records a completion. Ignored when nothing ran (done before its blocks, or never planned)
    /// or the ratio is implausible.
    public func record(_ task: TaskItem, actualHours: Double, now: Date) throws {
        guard !task.isOngoing, task.estimatedHours > 0, actualHours > 0 else { return }
        guard Self.ratioRange.contains(actualHours / task.estimatedHours) else { return }
        context.insert(DurationObservation(group: TimeOfDayMemory.group(for: task), estimatedHours: task.estimatedHours,
                                           actualHours: actualHours, recordedAt: now))
        if try context.fetchCount(FetchDescriptor<DurationObservation>()) > Self.capacity {
            let all = try context.fetch(FetchDescriptor<DurationObservation>(sortBy: [SortDescriptor(\.recordedAt, order: .reverse)]))
            all.dropFirst(Self.capacity).forEach(context.delete)
        }
        try context.save()
    }

    /// Every group with a learned factor, most observed first.
    public func learned(now: Date = Date()) throws -> [Learned] {
        let all = try context.fetch(FetchDescriptor<DurationObservation>())
        return Dictionary(grouping: all, by: \.group).compactMap { group, observations in
            Self.factor(from: observations, now: now).map { Learned(group: group, factor: $0, observations: observations.count) }
        }
        .sorted { ($0.observations, $1.group) > ($1.observations, $0.group) }
    }

    /// Factors by group, for the planner (worked out once per plan).
    public func factors(now: Date = Date()) throws -> [String: Double] {
        Dictionary(uniqueKeysWithValues: try learned(now: now).map { ($0.group, $0.factor) })
    }

    /// Recency-weighted actual / estimated time, bounded and rounded to 0.05, or nil when there's
    /// too little signal or it's close enough to 1.
    static func factor(from observations: [DurationObservation], now: Date) -> Double? {
        guard observations.count >= minimumObservations else { return nil }
        var actual = 0.0, estimated = 0.0
        for o in observations {
            let ageDays = max(now.timeIntervalSince(o.recordedAt), 0) / 86_400
            let weight = pow(0.5, ageDays / halfLifeDays)
            actual += o.actualHours * weight
            estimated += o.estimatedHours * weight
        }
        guard estimated > 0 else { return nil }
        let factor = min(max(((actual / estimated) * 20).rounded() / 20, factorRange.lowerBound), factorRange.upperBound)
        return abs(factor - 1) < deadBand ? nil : factor
    }

    /// The time the planner reserves for `hours` of estimate: rounded to 5 minutes, at least 5.
    public static func corrected(_ hours: Double, by factor: Double?) -> TimeInterval {
        guard let factor else { return hours * 3600 }
        let minutes = max((hours * factor * 60 / 5).rounded() * 5, 5)
        return minutes * 60
    }

    public func count() throws -> Int { try context.fetchCount(FetchDescriptor<DurationObservation>()) }

    public func reset() throws {
        try context.delete(model: DurationObservation.self)
        try context.save()
    }
}
