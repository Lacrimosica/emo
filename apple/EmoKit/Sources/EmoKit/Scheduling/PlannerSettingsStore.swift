import Foundation
import SwiftData

/// Loads and saves the user's planner settings.
@MainActor
public struct PlannerSettingsStore {
    public enum ValidationError: Error, Equatable {
        case dayEndNotAfterStart
        case dayBoundsOutOfRange
        case minimumChunkOutOfRange
        case budgetOutOfRange
        case defaultEnergyOutOfRange
    }

    public static let minimumChunkRange = 5...240
    public static let budgetRange = 0.0...24.0

    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    /// The saved settings, or the defaults if none were saved.
    public func load() -> PlannerSettings {
        (try? records().first?.settings) ?? .default
    }

    public func save(_ settings: PlannerSettings, now: Date = Date()) throws {
        try Self.validate(settings)
        let existing = try records()
        let record = existing.first ?? {
            let r = PlannerPreferences()
            context.insert(r)
            return r
        }()
        existing.dropFirst().forEach(context.delete)   // collapse sync duplicates
        record.apply(settings, now: now)
        try context.save()
    }

    public static func validate(_ s: PlannerSettings) throws(ValidationError) {
        guard (0...(24 * 60)).contains(s.dayStartMinutes), (0...(24 * 60)).contains(s.dayEndMinutes) else {
            throw .dayBoundsOutOfRange
        }
        guard s.dayEndMinutes > s.dayStartMinutes else { throw .dayEndNotAfterStart }
        guard minimumChunkRange.contains(s.minimumChunkMinutes) else { throw .minimumChunkOutOfRange }
        guard (1...5).allSatisfy({ budgetRange.contains(s.energyBudgetHours[$0] ?? -1) }) else { throw .budgetOutOfRange }
        guard (1...5).contains(s.defaultEnergy) else { throw .defaultEnergyOutOfRange }
    }

    /// Most recently updated first.
    private func records() throws -> [PlannerPreferences] {
        try context.fetch(FetchDescriptor<PlannerPreferences>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))
    }
}
