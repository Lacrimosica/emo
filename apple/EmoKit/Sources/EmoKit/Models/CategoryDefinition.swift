import Foundation
import SwiftData

/// A category the user can name, colour and give a weekly time target. Tasks refer to it by `key`.
///
/// CloudKit-compatible like `TaskItem` (every property defaulted, no unique constraints).
@Model
public final class CategoryDefinition {
    /// Stable identity stored on tasks (`TaskItem.categoryRaw`). Built-ins use their old raw values.
    public var key: String = UUID().uuidString
    public var name: String = ""
    /// "#RRGGBB".
    public var colorHex: String = "#888888"
    /// SF Symbol name.
    public var symbol: String = "tag"
    /// Hours per week the user wants in this category. 0 means no target.
    public var weeklyHours: Double = 0
    public var sortIndex: Int = 0

    public init(key: String = UUID().uuidString, name: String, colorHex: String, symbol: String, weeklyHours: Double = 0, sortIndex: Int = 0) {
        self.key = key
        self.name = name
        self.colorHex = colorHex
        self.symbol = symbol
        self.weeklyHours = weeklyHours
        self.sortIndex = sortIndex
    }

    public var taskCategory: TaskCategory { TaskCategory(key: key) }
    public var isBuiltIn: Bool { taskCategory.isBuiltIn }
}
