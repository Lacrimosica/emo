import Foundation
import SwiftData

/// Reads and records daily check-ins. One check-in per local day: recording again updates it.
@MainActor
public struct CheckIns {
    public static let scale = 1...5

    public enum ValidationError: Error, Equatable {
        case moodOutOfRange
        case energyOutOfRange
    }

    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func checkIn(for day: LocalDay) throws -> CheckIn? {
        try records(for: day).first
    }

    /// Creates or updates the check-in for `day`.
    @discardableResult
    public func record(mood: Int, energy: Int, for day: LocalDay, now: Date = Date()) throws -> CheckIn {
        guard Self.scale.contains(mood) else { throw ValidationError.moodOutOfRange }
        guard Self.scale.contains(energy) else { throw ValidationError.energyOutOfRange }

        let existing = try records(for: day)
        let checkIn: CheckIn
        if let first = existing.first {
            checkIn = first
            checkIn.mood = mood
            checkIn.energy = energy
            checkIn.updatedAt = now
            // Without a unique constraint, a sync merge could leave duplicates; collapse them.
            existing.dropFirst().forEach(context.delete)
        } else {
            checkIn = CheckIn(day: day, mood: mood, energy: energy, now: now)
            context.insert(checkIn)
        }
        try context.save()
        return checkIn
    }

    /// Most recently updated first.
    private func records(for day: LocalDay) throws -> [CheckIn] {
        try context.fetch(Self.descriptor(for: day))
    }

    /// Shared with SwiftUI's `@Query` so views observe the same record the domain reads.
    public static func descriptor(for day: LocalDay) -> FetchDescriptor<CheckIn> {
        let key = day.key
        return FetchDescriptor(
            predicate: #Predicate { $0.dayKey == key },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
    }
}
