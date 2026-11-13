import Foundation
import Testing
@testable import EmoKit

@Suite struct TimelineLayoutTests {
    func t(_ hour: Double) -> Date { Date(timeIntervalSince1970: hour * 3600) }

    @Test func nonOverlappingEventsGetFullWidth() {
        let slots = TimelineLayout.slots(for: [
            (id: "a", start: t(9), end: t(10)),
            (id: "b", start: t(10), end: t(11)),   // touching, not overlapping
        ])
        #expect(slots["a"] == .init(column: 0, columnCount: 1))
        #expect(slots["b"] == .init(column: 0, columnCount: 1))
    }

    @Test func overlappingEventsShareTheWidth() {
        let slots = TimelineLayout.slots(for: [
            (id: "a", start: t(9), end: t(11)),
            (id: "b", start: t(10), end: t(12)),
            (id: "c", start: t(13), end: t(14)),
        ])
        #expect(slots["a"] == .init(column: 0, columnCount: 2))
        #expect(slots["b"] == .init(column: 1, columnCount: 2))
        #expect(slots["c"] == .init(column: 0, columnCount: 1))
    }

    @Test func freedColumnsAreReusedWithinACluster() {
        // a overlaps b and c; b and c don't overlap each other, so c reuses b's column.
        let slots = TimelineLayout.slots(for: [
            (id: "a", start: t(9), end: t(12)),
            (id: "b", start: t(9), end: t(10)),
            (id: "c", start: t(10.5), end: t(11)),
        ])
        #expect(slots["a"] == .init(column: 0, columnCount: 2))
        #expect(slots["b"] == .init(column: 1, columnCount: 2))
        #expect(slots["c"] == .init(column: 1, columnCount: 2))
    }
}
