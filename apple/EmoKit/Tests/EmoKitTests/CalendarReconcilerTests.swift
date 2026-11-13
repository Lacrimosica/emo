import Foundation
import SwiftData
import Testing
@testable import EmoKit

@MainActor
@Suite struct CalendarReconcilerTests {
    let container = try! EmoStore.makeContainer(.inMemory)
    var context: ModelContext { container.mainContext }
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Rome")!
        return c
    }()
    let day = LocalDay(year: 2026, month: 11, day: 13)
    var reconciler: CalendarReconciler { CalendarReconciler(context: context, calendar: calendar) }
    var engine: CalendarEngine { CalendarEngine(context: context) }

    func at(_ hour: Int, _ minute: Int = 0, on d: LocalDay? = nil) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: (d ?? day).start(in: calendar))!
    }
    var window: DateInterval { DateInterval(start: day.start(in: calendar), end: day.adding(days: 14, calendar: calendar).start(in: calendar)) }

    func snapshot(_ events: [ExternalEvent], sources: Set<String> = ["work"]) -> CalendarSnapshot {
        CalendarSnapshot(provider: "apple-calendar", sources: sources, window: window, events: events)
    }
    func meeting(_ h1: Int, _ h2: Int, id: String = "m1", title: String = "Standup", source: String = "work", on d: LocalDay? = nil) -> ExternalEvent {
        ExternalEvent(externalID: id, sourceID: source, title: title, start: at(h1, on: d), end: at(h2, on: d))
    }
    func linked() throws -> [CalendarEvent] { try engine.events(on: day, calendar: calendar).filter { $0.origin == .linked } }

    @Test func newEventsBecomeLinkedFixedEvents() throws {
        let r = try reconciler.apply(snapshot([meeting(10, 11)]), now: at(7))
        #expect(r.added == 1)
        let event = try #require(try linked().first)
        #expect(event.kind == .fixed && event.title == "Standup" && !event.isUserEditable)
        #expect(try context.fetchCount(FetchDescriptor<ExternalLink>()) == 1)
    }

    @Test func reapplyingTheSameSnapshotChangesNothing() throws {
        try reconciler.apply(snapshot([meeting(10, 11)]), now: at(7))
        let r = try reconciler.apply(snapshot([meeting(10, 11)]), now: at(7, 5))
        #expect(!r.changed)
        #expect(try linked().count == 1)
    }

    @Test func movedEventIsUpdatedInPlace() throws {
        try reconciler.apply(snapshot([meeting(10, 11)]), now: at(7))
        let id = try #require(try linked().first?.id)
        let r = try reconciler.apply(snapshot([meeting(14, 15, title: "Standup (moved)")]), now: at(7, 5))
        #expect(r.updated == 1 && r.added == 0)
        let event = try #require(try linked().first)
        #expect(event.id == id && event.start == at(14) && event.title == "Standup (moved)")
    }

    @Test func eventMissingFromItsSourceIsRemoved() throws {
        try reconciler.apply(snapshot([meeting(10, 11, id: "a"), meeting(12, 13, id: "b")]), now: at(7))
        let r = try reconciler.apply(snapshot([meeting(10, 11, id: "a")]), now: at(7, 5))
        #expect(r.removed == 1)
        #expect(try linked().map(\.title) == ["Standup"])
        #expect(try context.fetchCount(FetchDescriptor<ExternalLink>()) == 1)
    }

    @Test func deletedThenReaddedEventComesBack() throws {
        try reconciler.apply(snapshot([meeting(10, 11)]), now: at(7))
        try reconciler.apply(snapshot([]), now: at(7, 1))
        let r = try reconciler.apply(snapshot([meeting(10, 11)]), now: at(7, 2))
        #expect(r.added == 1)
        #expect(try linked().count == 1)
    }

    @Test func eventsOutsideTheWindowAreLeftAsHistory() throws {
        let yesterday = day.adding(days: -1, calendar: calendar)
        let old = CalendarSnapshot(provider: "apple-calendar", sources: ["work"],
                                   window: DateInterval(start: yesterday.start(in: calendar), end: window.end),
                                   events: [meeting(9, 10, id: "old", on: yesterday)])
        try reconciler.apply(old, now: at(7, on: yesterday))
        try reconciler.apply(snapshot([]), now: at(7))      // today's window no longer covers yesterday
        #expect(try engine.events(on: yesterday, calendar: calendar).count == 1)
    }

    @Test func otherSourcesAreUntouchedAndDeselectingRemovesThem() throws {
        try reconciler.apply(snapshot([meeting(10, 11, id: "w"), meeting(18, 19, id: "h", title: "Dinner", source: "home")],
                                      sources: ["work", "home"]), now: at(7))
        try reconciler.apply(snapshot([meeting(10, 11, id: "w")], sources: ["work"]), now: at(7, 1))
        #expect(try linked().count == 2)   // "home" wasn't covered by this snapshot

        let r = try reconciler.removeAll(provider: "apple-calendar", keeping: ["work"], now: at(7, 2))
        #expect(r.removed == 1)
        #expect(try linked().map(\.title) == ["Standup"])
        try reconciler.removeAll(provider: "apple-calendar", now: at(7, 3))
        #expect(try linked().isEmpty)
        #expect(try context.fetchCount(FetchDescriptor<ExternalLink>()) == 0)
    }

    @Test func newMeetingEjectsCollidingTaskBlocksAndReplans() throws {
        try CheckIns(context: context).record(mood: 3, energy: 5, for: day)
        try Backlog(context: context).add(TaskDraft(name: "Deep work", estimatedHours: 2))
        try DayPlanning(context: context, calendar: calendar).plan(day, now: at(7))   // 9–11

        let r = try reconciler.apply(snapshot([meeting(9, 10)]), now: at(7, 30))

        #expect(r.replannedDays.contains(day))
        let blocks = try engine.events(on: day, calendar: calendar).filter { $0.kind == .taskBlock }
        #expect(blocks.map(\.start) == [at(10)])
        #expect(blocks.reduce(0) { $0 + $1.duration } == 2 * 3600)
    }

    @Test func unplannedDaysStayUnplanned() throws {
        try Backlog(context: context).add(TaskDraft(name: "Something", estimatedHours: 1))
        let r = try reconciler.apply(snapshot([meeting(9, 10)]), now: at(7))
        #expect(r.replannedDays.isEmpty)
        #expect(try engine.events(on: day, calendar: calendar).filter { $0.kind == .taskBlock }.isEmpty)
    }

    @Test func pinnedBlocksThatCollideAreReportedNotMoved() throws {
        let task = try Backlog(context: context).add(TaskDraft(name: "Gym", estimatedHours: 1))
        let pinned = try TaskLifecycle(context: context, calendar: calendar).pin(task, start: at(17), end: at(18), now: at(7))
        let r = try reconciler.apply(snapshot([meeting(17, 18, title: "Late call")]), now: at(7, 5))
        #expect(r.pinnedConflicts == [pinned.id])
        #expect(pinned.start == at(17))
    }

    @Test func allDayEventsDontBlockPlanning() throws {
        try CheckIns(context: context).record(mood: 3, energy: 5, for: day)
        try Backlog(context: context).add(TaskDraft(name: "Work", estimatedHours: 1))
        let allDay = ExternalEvent(externalID: "hol", sourceID: "work", title: "Conference", start: day.start(in: calendar),
                                   end: day.end(in: calendar), isAllDay: true)
        try reconciler.apply(snapshot([allDay]), now: at(7))
        try DayPlanning(context: context, calendar: calendar).plan(day, now: at(7))
        #expect(try engine.events(on: day, calendar: calendar).first { $0.kind == .taskBlock }?.start == at(9))
    }

    @Test func linkedEventsCannotBeEditedByTheUserButCanBeByTheReconciler() throws {
        try reconciler.apply(snapshot([meeting(10, 11)]), now: at(7))
        let event = try #require(try linked().first)
        #expect(throws: CalendarEngine.EditError.notUserEditable) { try engine.move(event, to: at(12)) }
    }
}
