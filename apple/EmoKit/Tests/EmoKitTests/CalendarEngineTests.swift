import Foundation
import SwiftData
import Testing
@testable import EmoKit

@MainActor
@Suite struct CalendarEngineTests {
    let container = try! EmoStore.makeContainer(.inMemory)
    var engine: CalendarEngine { CalendarEngine(context: container.mainContext) }
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Rome")!
        return c
    }()
    let day = LocalDay(year: 2026, month: 11, day: 13)

    func at(_ hour: Int, _ minute: Int = 0, on day: LocalDay? = nil) -> Date {
        let d = day ?? self.day
        return calendar.date(byAdding: DateComponents(hour: hour, minute: minute), to: d.start(in: calendar))!
    }

    @Test func createdFixedEventAppearsOnItsDay() throws {
        try engine.createFixedEvent(title: "  Dentist ", start: at(10), end: at(11))
        let events = try engine.events(on: day, calendar: calendar)
        #expect(events.count == 1)
        let event = try #require(events.first)
        #expect(event.title == "Dentist")
        #expect(event.kind == .fixed)
        #expect(event.origin == .local)
        #expect(!event.isLocked)
    }

    @Test func dayQueryIncludesOverlapsAndExcludesOtherDays() throws {
        let yesterday = day.adding(days: -1, calendar: calendar)
        let tomorrow = day.adding(days: 1, calendar: calendar)
        try engine.createFixedEvent(title: "Overnight", start: at(23, on: yesterday), end: at(1))
        try engine.createFixedEvent(title: "Lunch", start: at(12), end: at(13))
        try engine.createFixedEvent(title: "Late", start: at(23), end: at(1, on: tomorrow))
        try engine.createFixedEvent(title: "Yesterday", start: at(9, on: yesterday), end: at(10, on: yesterday))
        try engine.createFixedEvent(title: "Ends at midnight", start: at(22, on: yesterday), end: day.start(in: calendar))

        #expect(try engine.events(on: day, calendar: calendar).map(\.title) == ["Overnight", "Lunch", "Late"])
    }

    @Test func invalidEventsAreRejected() throws {
        #expect(throws: CalendarEngine.EditError.emptyTitle) {
            try engine.createFixedEvent(title: " ", start: at(9), end: at(10))
        }
        #expect(throws: CalendarEngine.EditError.endNotAfterStart) {
            try engine.createFixedEvent(title: "Backwards", start: at(10), end: at(9))
        }
        #expect(throws: CalendarEngine.EditError.tooShort) {
            try engine.createFixedEvent(title: "Blip", start: at(9), end: at(9, 2))
        }
        #expect(try engine.events(on: day, calendar: calendar).isEmpty)
    }

    @Test func moveKeepsDuration() throws {
        let event = try engine.createFixedEvent(title: "Gym", start: at(7), end: at(8, 30))
        try engine.move(event, to: at(18))
        #expect(event.start == at(18))
        #expect(event.end == at(19, 30))
    }

    @Test func updateEditsOnlyGivenFieldsAndValidates() throws {
        let event = try engine.createFixedEvent(title: "Call", start: at(9), end: at(10), notes: "dial in")
        try engine.update(event, title: "Client call", end: at(10, 30))
        #expect(event.title == "Client call")
        #expect(event.notes == "dial in")
        #expect(event.start == at(9))
        #expect(event.end == at(10, 30))

        #expect(throws: CalendarEngine.EditError.endNotAfterStart) {
            try engine.update(event, start: at(11))
        }
        #expect(event.start == at(9))
    }

    @Test func deleteRemovesEvent() throws {
        let event = try engine.createFixedEvent(title: "Cancelled", start: at(9), end: at(10))
        try engine.delete(event)
        #expect(try engine.events(on: day, calendar: calendar).isEmpty)
    }

    @Test func linkedEventsCannotBeEditedByTheUser() throws {
        let linked = CalendarEvent(title: "From Calendar.app", start: at(9), end: at(10), kind: .fixed, origin: .linked)
        container.mainContext.insert(linked)
        try container.mainContext.save()

        #expect(throws: CalendarEngine.EditError.notUserEditable) { try engine.move(linked, to: at(11)) }
        #expect(throws: CalendarEngine.EditError.notUserEditable) { try engine.update(linked, title: "Mine now") }
        #expect(throws: CalendarEngine.EditError.notUserEditable) { try engine.delete(linked) }
        #expect(linked.start == at(9))
    }

    @Test func snappingRoundsToNearestStep() {
        #expect(at(9, 7).snapped(toMinutes: 15, calendar: calendar) == at(9))
        #expect(at(9, 8).snapped(toMinutes: 15, calendar: calendar) == at(9, 15))
        #expect(at(9, 53).snapped(toMinutes: 15, calendar: calendar) == at(10))
    }
}
