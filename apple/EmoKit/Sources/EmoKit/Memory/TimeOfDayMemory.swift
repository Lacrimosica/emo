import Foundation
import SwiftData

/// A hint about when the user does a kind of task (ticket 20): a completion, a block moved there
/// by hand, or (negative) a skipped block.
///
/// CloudKit-compatible (ADR 0001): defaulted scalars, no relationships or unique constraints.
@Model
public final class TimeOfDayObservation {
    public var id: UUID = UUID()
    /// What the hint is about: `area:<name>` or `category:<raw>` (see `TimeOfDayMemory.group`).
    public var group: String = ""
    /// Minutes after local midnight.
    public var minuteOfDay: Int = 0
    public var weight: Double = 1
    public var recordedAt: Date = Date()

    init(group: String, minuteOfDay: Int, weight: Double, recordedAt: Date) {
        self.group = group
        self.minuteOfDay = minuteOfDay
        self.weight = weight
        self.recordedAt = recordedAt
    }
}

/// A stretch of the day a kind of task tends to happen in.
public struct PreferredWindow: Equatable, Sendable {
    public var startMinutes: Int
    public var endMinutes: Int

    public init(startMinutes: Int, endMinutes: Int) {
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
    }

    func interval(on day: LocalDay, calendar: Calendar) -> DateInterval {
        let start = day.start(in: calendar)
        return DateInterval(start: start.addingTimeInterval(TimeInterval(startMinutes * 60)),
                            end: start.addingTimeInterval(TimeInterval(endMinutes * 60)))
    }
}

/// Learns when the user does each kind of task and gives the planner a preferred window for it.
/// A soft preference only: it never changes which tasks are planned or in what priority.
@MainActor
public struct TimeOfDayMemory {
    public enum Signal: Double {
        case completed = 1
        /// Moved or resized by hand: the clearest statement of "this is when I do it".
        case movedByHand = 2
        case skipped = -1
    }

    public struct Learned: Equatable, Sendable, Identifiable {
        public var group: String
        public var window: PreferredWindow
        /// How many hints it's based on.
        public var observations: Int
        public var id: String { group }

        /// The area or category name, for display.
        public var name: String { String(group.split(separator: ":", maxSplits: 1).last ?? "") }
        public var isArea: Bool { group.hasPrefix("area:") }
    }

    public static let capacity = 1000
    public static let windowHours = 4
    /// Net weight needed before anything is learned for a group.
    static let minimumWeight = 3.0
    /// Share of a group's positive weight the best window must hold.
    static let minimumShare = 0.5

    private let context: ModelContext
    private let calendar: Calendar

    public init(context: ModelContext, calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
    }

    /// Tasks group by list area, or by category when they have none.
    public static func group(for task: TaskItem) -> String {
        if let area = task.listArea?.trimmingCharacters(in: .whitespaces), !area.isEmpty {
            return "area:\(area.lowercased())"
        }
        return "category:\(task.category.rawValue)"
    }

    public func record(_ signal: Signal, for task: TaskItem, at date: Date) throws {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        context.insert(TimeOfDayObservation(group: Self.group(for: task), minuteOfDay: (c.hour ?? 0) * 60 + (c.minute ?? 0),
                                            weight: signal.rawValue, recordedAt: date))
        if try context.fetchCount(FetchDescriptor<TimeOfDayObservation>()) > Self.capacity {
            let all = try context.fetch(FetchDescriptor<TimeOfDayObservation>(sortBy: [SortDescriptor(\.recordedAt, order: .reverse)]))
            all.dropFirst(Self.capacity).forEach(context.delete)
        }
        try context.save()
    }

    /// The preferred window for `task`'s group, if one has been learned.
    public func preferredWindow(for task: TaskItem) throws -> PreferredWindow? {
        try learned().first { $0.group == Self.group(for: task) }?.window
    }

    /// Every group with a learned window, most observed first.
    public func learned() throws -> [Learned] {
        let all = try context.fetch(FetchDescriptor<TimeOfDayObservation>())
        return Dictionary(grouping: all, by: \.group).compactMap { group, observations in
            Self.window(from: observations).map { Learned(group: group, window: $0, observations: observations.count) }
        }
        .sorted { ($0.observations, $1.group) > ($1.observations, $0.group) }
    }

    /// The `windowHours` stretch (on the hour, within the day) with the most net weight, if the
    /// group has enough signal and that stretch holds most of it.
    static func window(from observations: [TimeOfDayObservation]) -> PreferredWindow? {
        var hours = [Double](repeating: 0, count: 24)
        for o in observations { hours[min(max(o.minuteOfDay / 60, 0), 23)] += o.weight }
        let positive = hours.filter { $0 > 0 }.reduce(0, +)
        guard hours.reduce(0, +) >= minimumWeight, positive > 0 else { return nil }
        var best = (start: 0, weight: -Double.infinity)
        for start in 0...(24 - windowHours) {
            let weight = hours[start..<(start + windowHours)].reduce(0, +)
            if weight > best.weight { best = (start, weight) }
        }
        guard best.weight >= positive * minimumShare else { return nil }
        return PreferredWindow(startMinutes: best.start * 60, endMinutes: (best.start + windowHours) * 60)
    }

    public func reset() throws {
        try context.delete(model: TimeOfDayObservation.self)
        try context.save()
    }
}
