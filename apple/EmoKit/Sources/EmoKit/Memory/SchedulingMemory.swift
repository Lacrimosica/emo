import Foundation
import SwiftData

/// One time the user sized a task themselves (ticket 18).
///
/// CloudKit-compatible (ADR 0001): defaulted scalars, no relationships or unique constraints.
@Model
public final class SizingObservation {
    public var id: UUID = UUID()
    /// Normalized title keywords, space-separated.
    public var keywords: String = ""
    public var area: String?
    public var roleRaw: String?
    public var estimatedHours: Double = 1
    public var energyCostRaw: String = EnergyCost.medium.rawValue
    public var categoryRaw: String = TaskCategory.personal.rawValue
    public var recordedAt: Date = Date()

    init(keywords: [String], area: String?, role: ListRole?, estimatedHours: Double,
         energyCost: EnergyCost, category: TaskCategory, recordedAt: Date) {
        self.keywords = keywords.joined(separator: " ")
        self.area = area
        self.roleRaw = role?.rawValue
        self.estimatedHours = estimatedHours
        self.energyCostRaw = energyCost.rawValue
        self.categoryRaw = category.rawValue
        self.recordedAt = recordedAt
    }

    var keywordSet: Set<String> { Set(keywords.split(separator: " ").map(String.init)) }
}

/// Remembers how the user sizes tasks and suggests sizing for similar new ones (ticket 18).
///
/// `record` takes a task the user just sized (created, or reviewed after import); `suggest` finds
/// past tasks with matching title keywords, preferring the same list area, and returns their
/// recency-weighted sizing, or nil when nothing matches confidently.
@MainActor
public struct SchedulingMemory {
    public struct Suggestion: Equatable, Sendable {
        public var estimatedHours: Double
        public var energyCost: EnergyCost
        public var category: TaskCategory
        /// How many past tasks it's based on.
        public var basis: Int
    }

    /// Observations kept; the oldest go first.
    public static let capacity = 500
    /// Share of the new title's keywords a past task must have to count as similar.
    static let minimumOverlap = 0.5
    /// Each step back in time halves an observation's weight after this many newer ones.
    static let halfLifeObservations = 2.0

    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func record(_ task: TaskItem, now: Date = Date()) throws {
        guard !task.isOngoing else { return }   // sized per session, not as a whole
        let keywords = Self.keywords(task.name)
        guard !keywords.isEmpty else { return }
        context.insert(SizingObservation(keywords: keywords, area: task.listArea, role: task.listRole,
                                         estimatedHours: task.estimatedHours, energyCost: task.energyCost,
                                         category: task.category, recordedAt: now))
        if try context.fetchCount(FetchDescriptor<SizingObservation>()) > Self.capacity {
            let all = try context.fetch(FetchDescriptor<SizingObservation>(sortBy: [SortDescriptor(\.recordedAt, order: .reverse)]))
            all.dropFirst(Self.capacity).forEach(context.delete)
        }
        try context.save()
    }

    public func suggest(for title: String, area: String?, role: ListRole? = nil) throws -> Suggestion? {
        let query = Set(Self.keywords(title))
        guard !query.isEmpty else { return nil }
        let all = try context.fetch(FetchDescriptor<SizingObservation>(sortBy: [SortDescriptor(\.recordedAt, order: .reverse)]))

        var matches: [(observation: SizingObservation, score: Double)] = []
        for observation in all {
            let shared = observation.keywordSet.intersection(query).count
            guard shared > 0 else { continue }
            var score = Double(shared) / Double(query.count)
            if let area, let theirs = observation.area {
                score += area.caseInsensitiveCompare(theirs) == .orderedSame ? 0.25 : -0.25
            }
            if score >= Self.minimumOverlap { matches.append((observation, score)) }
        }
        guard let best = matches.map(\.score).max() else { return nil }
        // Keep only the closest matches (e.g. the same area beats another area's similar task).
        let closest = matches.filter { $0.score >= best - 0.001 }

        var hours = 0.0, totalWeight = 0.0
        var energyVotes: [EnergyCost: Double] = [:], categoryVotes: [TaskCategory: Double] = [:]
        for (index, match) in closest.enumerated() {   // newest first
            let weight = pow(0.5, Double(index) / Self.halfLifeObservations)
            hours += match.observation.estimatedHours * weight
            totalWeight += weight
            energyVotes[EnergyCost(rawValue: match.observation.energyCostRaw) ?? .medium, default: 0] += weight
            categoryVotes[TaskCategory(rawValue: match.observation.categoryRaw) ?? .personal, default: 0] += weight
        }
        let estimate = min(max(((hours / totalWeight) * 4).rounded() / 4, 0.25), 24)
        return Suggestion(estimatedHours: estimate,
                          energyCost: energyVotes.max { $0.value < $1.value }!.key,
                          category: categoryVotes.max { $0.value < $1.value }!.key,
                          basis: closest.count)
    }

    /// How many sized tasks are remembered.
    public func count() throws -> Int { try context.fetchCount(FetchDescriptor<SizingObservation>()) }

    public func reset() throws {
        try context.delete(model: SizingObservation.self)
        try context.save()
    }

    private static let stopwords: Set<String> = [
        "the", "and", "for", "with", "from", "into", "about", "this", "that", "some", "out", "off",
        "get", "make", "do", "to", "of", "on", "in", "at", "a", "an", "my", "our", "your",
    ]

    /// Lowercased words of three letters or more, minus filler words, with a trailing plural "s" dropped.
    static func keywords(_ title: String) -> [String] {
        var seen: Set<String> = []
        return title.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map { word -> String in
                let w = String(word)
                return w.count > 3 && w.hasSuffix("s") && !w.hasSuffix("ss") ? String(w.dropLast()) : w
            }
            .filter { $0.count >= 3 && !stopwords.contains($0) && seen.insert($0).inserted }
    }
}
