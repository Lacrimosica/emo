import Foundation
import SwiftData

/// The user's self-reported mood and energy for one local day. Energy sizes the day's work budget.
///
/// CloudKit-compatible (see ADR 0001): defaulted properties, no unique constraint on `dayKey`;
/// `CheckIns` enforces one record per day in code.
@Model
public final class CheckIn {
    public var id: UUID = UUID()
    /// `LocalDay.key` ("YYYY-MM-DD") of the day this check-in belongs to.
    public var dayKey: String = ""
    /// 1 (low) … 5 (high).
    public var mood: Int = 3
    /// 1 (low) … 5 (high).
    public var energy: Int = 3
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public init(day: LocalDay, mood: Int, energy: Int, now: Date = Date()) {
        self.dayKey = day.key
        self.mood = mood
        self.energy = energy
        self.createdAt = now
        self.updatedAt = now
    }

    public var day: LocalDay? { LocalDay(key: dayKey) }
}
