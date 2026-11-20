import Foundation
import SwiftData

/// The user's categories: the four built-ins plus any they add. Planning reads the weekly targets
/// from here; the Settings screen edits them.
public struct CategoryCatalog {
    public static let weeklyHoursRange: ClosedRange<Double> = 0...40

    public enum CatalogError: Error, Equatable {
        case emptyName
        case builtInCannotBeDeleted
    }

    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    /// Adds the built-ins the first time the store is opened. Safe to call on every launch.
    public func seedBuiltInsIfNeeded() throws {
        guard try context.fetchCount(FetchDescriptor<CategoryDefinition>()) == 0 else { return }
        for (index, category) in TaskCategory.builtIns.enumerated() {
            let defaults = TaskCategory.builtInDefaults[category.key]!
            context.insert(CategoryDefinition(key: category.key, name: defaults.name, colorHex: defaults.colorHex,
                                              symbol: defaults.symbol, sortIndex: index))
        }
        try context.save()
    }

    /// Every category, in the user's order.
    public func all() throws -> [CategoryDefinition] {
        try context.fetch(FetchDescriptor<CategoryDefinition>(sortBy: [SortDescriptor(\.sortIndex), SortDescriptor(\.name)]))
    }

    public func definition(forKey key: String) throws -> CategoryDefinition? {
        var descriptor = FetchDescriptor<CategoryDefinition>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Weekly hour targets by category key, for categories with a target.
    public func weeklyTargets() throws -> [String: TimeInterval] {
        try all().reduce(into: [:]) { targets, category in
            if category.weeklyHours > 0 { targets[category.key] = category.weeklyHours * 3600 }
        }
    }

    @discardableResult
    public func add(name: String, colorHex: String, symbol: String = "tag", weeklyHours: Double = 0) throws -> CategoryDefinition {
        let name = try Self.validName(name)
        let next = (try all().map(\.sortIndex).max() ?? -1) + 1
        let category = CategoryDefinition(name: name, colorHex: colorHex, symbol: symbol,
                                          weeklyHours: Self.clampedHours(weeklyHours), sortIndex: next)
        context.insert(category)
        try context.save()
        return category
    }

    /// `symbol`: nil keeps the current one.
    public func update(_ category: CategoryDefinition, name: String, colorHex: String, weeklyHours: Double,
                       symbol: String? = nil) throws {
        category.name = try Self.validName(name)
        category.colorHex = colorHex
        if let symbol { category.symbol = symbol }
        category.weeklyHours = Self.clampedHours(weeklyHours)
        try context.save()
    }

    /// Deletes a custom category. Its tasks move to Personal. Returns how many tasks moved.
    @discardableResult
    public func delete(_ category: CategoryDefinition) throws -> Int {
        guard !category.isBuiltIn else { throw CatalogError.builtInCannotBeDeleted }
        let key = category.key
        let tasks = try context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.categoryRaw == key }))
        for task in tasks { task.categoryRaw = TaskCategory.personal.key }
        context.delete(category)
        try context.save()
        return tasks.count
    }

    /// Name of a category key, falling back to the built-in default (or the key) when it isn't stored.
    public static func name(for key: String, in categories: [CategoryDefinition]) -> String {
        categories.first { $0.key == key }?.name ?? TaskCategory(key: key).defaultName
    }

    static func validName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CatalogError.emptyName }
        return trimmed
    }

    static func clampedHours(_ hours: Double) -> Double {
        min(max((hours * 4).rounded() / 4, weeklyHoursRange.lowerBound), weeklyHoursRange.upperBound)
    }
}
