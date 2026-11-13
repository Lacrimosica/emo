import Foundation

/// A calendar day as the user experiences it (in their local timezone), independent of clock time.
///
/// Day-scoped records (check-ins, schedules) are keyed by `LocalDay.key` ("YYYY-MM-DD") rather than
/// by a `Date`, so a record never drifts to a neighbouring day because of UTC conversion — the bug
/// the legacy web engine had with `toISOString().split('T')[0]`.
public struct LocalDay: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The local day that `date` falls on in `calendar`'s timezone.
    public init(_ date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year!, month: c.month!, day: c.day!)
    }

    public static func today(calendar: Calendar = .current, now: Date = Date()) -> LocalDay {
        LocalDay(now, calendar: calendar)
    }

    /// Parses a "YYYY-MM-DD" key.
    public init?(key: String) {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    public var key: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public var description: String { key }

    /// The first instant of this day in `calendar`'s timezone.
    public func start(in calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    /// The first instant of the following day (exclusive end of this day). Handles DST-length days.
    public func end(in calendar: Calendar = .current) -> Date {
        adding(days: 1, calendar: calendar).start(in: calendar)
    }

    public func adding(days: Int, calendar: Calendar = .current) -> LocalDay {
        // Step from midday to stay clear of DST transitions at midnight.
        let noon = calendar.date(byAdding: .hour, value: 12, to: start(in: calendar))!
        return LocalDay(calendar.date(byAdding: .day, value: days, to: noon)!, calendar: calendar)
    }

    public static func < (lhs: LocalDay, rhs: LocalDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}
