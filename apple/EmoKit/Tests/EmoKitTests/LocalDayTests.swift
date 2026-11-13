import Foundation
import Testing
@testable import EmoKit

@Suite struct LocalDayTests {
    private func calendar(_ tz: String) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: tz)!
        return c
    }

    private func date(_ iso: String) -> Date {
        try! Date(iso, strategy: .iso8601)
    }

    @Test func dayFollowsLocalTimezoneNotUTC() {
        // 23:30 in New York on Jan 5 is already Jan 6 in UTC.
        let instant = date("2026-01-06T04:30:00Z")
        #expect(LocalDay(instant, calendar: calendar("America/New_York")).key == "2026-01-05")
        #expect(LocalDay(instant, calendar: calendar("UTC")).key == "2026-01-06")
    }

    @Test func justBeforeAndAfterLocalMidnight() {
        let rome = calendar("Europe/Rome")
        #expect(LocalDay(date("2026-03-10T22:59:59Z"), calendar: rome).key == "2026-03-10")
        #expect(LocalDay(date("2026-03-10T23:00:00Z"), calendar: rome).key == "2026-03-11")
    }

    @Test func keyRoundTrips() {
        let day = LocalDay(year: 2026, month: 2, day: 9)
        #expect(day.key == "2026-02-09")
        #expect(LocalDay(key: "2026-02-09") == day)
        #expect(LocalDay(key: "nonsense") == nil)
        #expect(LocalDay(key: "2026-13-01") == nil)
    }

    @Test func addingDaysAcrossMonthYearAndDST() {
        let ny = calendar("America/New_York")
        #expect(LocalDay(year: 2026, month: 12, day: 31).adding(days: 1, calendar: ny).key == "2027-01-01")
        #expect(LocalDay(year: 2026, month: 3, day: 1).adding(days: -1, calendar: ny).key == "2026-02-28")
        // US DST starts 2026-03-08: that day is 23 hours long.
        let dstDay = LocalDay(year: 2026, month: 3, day: 8)
        #expect(dstDay.adding(days: 1, calendar: ny).key == "2026-03-09")
        #expect(dstDay.end(in: ny).timeIntervalSince(dstDay.start(in: ny)) == 23 * 3600)
    }

    @Test func startOfWeekFollowsTheCalendarsFirstWeekday() {
        var monday = calendar("Europe/Rome"); monday.firstWeekday = 2
        var sunday = calendar("America/New_York"); sunday.firstWeekday = 1
        let friday = LocalDay(year: 2026, month: 11, day: 13)
        #expect(friday.startOfWeek(calendar: monday).key == "2026-11-09")
        #expect(friday.startOfWeek(calendar: sunday).key == "2026-11-08")
        let mondayItself = LocalDay(year: 2026, month: 11, day: 9)
        #expect(mondayItself.startOfWeek(calendar: monday) == mondayItself)
        #expect(mondayItself.days(7, calendar: monday).last?.key == "2026-11-15")
    }

    @Test func ordering() {
        #expect(LocalDay(year: 2026, month: 1, day: 31) < LocalDay(year: 2026, month: 2, day: 1))
    }
}
