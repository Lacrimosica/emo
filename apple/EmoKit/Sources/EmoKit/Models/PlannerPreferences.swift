import Foundation
import SwiftData

/// The stored form of `PlannerSettings`. Kept in SwiftData (not UserDefaults) so it syncs with
/// the rest of the user's data. One record; `PlannerSettingsStore` collapses duplicates.
/// CloudKit-compatible (ADR 0001): plain defaulted scalars only.
@Model
public final class PlannerPreferences {
    public var dayStartMinutes: Int = 9 * 60
    public var dayEndMinutes: Int = 22 * 60
    public var minimumChunkMinutes: Int = 30
    public var budgetEnergy1: Double = 2
    public var budgetEnergy2: Double = 3.5
    public var budgetEnergy3: Double = 5
    public var budgetEnergy4: Double = 6.5
    public var budgetEnergy5: Double = 8
    public var defaultEnergy: Int = 3
    public var updatedAt: Date = Date()

    init() {}

    var settings: PlannerSettings {
        PlannerSettings(
            dayStartMinutes: dayStartMinutes,
            dayEndMinutes: dayEndMinutes,
            minimumChunkMinutes: minimumChunkMinutes,
            energyBudgetHours: [1: budgetEnergy1, 2: budgetEnergy2, 3: budgetEnergy3, 4: budgetEnergy4, 5: budgetEnergy5],
            defaultEnergy: defaultEnergy
        )
    }

    func apply(_ s: PlannerSettings, now: Date) {
        dayStartMinutes = s.dayStartMinutes
        dayEndMinutes = s.dayEndMinutes
        minimumChunkMinutes = s.minimumChunkMinutes
        budgetEnergy1 = s.energyBudgetHours[1] ?? 0
        budgetEnergy2 = s.energyBudgetHours[2] ?? 0
        budgetEnergy3 = s.energyBudgetHours[3] ?? 0
        budgetEnergy4 = s.energyBudgetHours[4] ?? 0
        budgetEnergy5 = s.energyBudgetHours[5] ?? 0
        defaultEnergy = s.defaultEnergy
        updatedAt = now
    }
}
