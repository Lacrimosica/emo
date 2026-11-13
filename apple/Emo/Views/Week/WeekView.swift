import EmoKit
import SwiftData
import SwiftUI

/// Seven days of the internal calendar side by side. Clicking a day or a block opens it in Today.
struct WeekView: View {
    let weekStart: LocalDay
    let today: LocalDay
    let onChangeWeek: (LocalDay) -> Void
    let onOpenDay: (LocalDay) -> Void

    @Query private var events: [CalendarEvent]
    @Query private var checkIns: [CheckIn]

    static let hourHeight: CGFloat = 36
    static let labelWidth: CGFloat = 44

    private let calendar = Calendar.current

    init(weekStart: LocalDay, today: LocalDay, onChangeWeek: @escaping (LocalDay) -> Void, onOpenDay: @escaping (LocalDay) -> Void) {
        self.weekStart = weekStart
        self.today = today
        self.onChangeWeek = onChangeWeek
        self.onOpenDay = onOpenDay
        let days = weekStart.days(7)
        self._events = Query(CalendarEngine.descriptor(from: days[0], through: days[6]))
        let keys = days.map(\.key)
        self._checkIns = Query(filter: #Predicate<CheckIn> { keys.contains($0.dayKey) })
    }

    private var days: [LocalDay] { weekStart.days(7, calendar: calendar) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.clear.frame(width: Self.labelWidth)
                ForEach(days, id: \.self) { day in
                    DayHeader(day: day, isToday: day == today, energy: energy(on: day),
                              allDay: events.filter { $0.isAllDay && $0.start < day.end(in: calendar) && $0.end > day.start(in: calendar) }.map(\.title))
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture { onOpenDay(day) }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint("Opens this day")
                }
            }
            .padding(.vertical, 8)
            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    HStack(alignment: .top, spacing: 0) {
                        HourLabels(calendar: calendar, day: weekStart)
                            .frame(width: Self.labelWidth)
                        ForEach(days, id: \.self) { day in
                            DayColumn(
                                day: day,
                                isToday: day == today,
                                events: events.filter { !$0.isAllDay && $0.start < day.end(in: calendar) && $0.end > day.start(in: calendar) },
                                calendar: calendar,
                                onOpen: { onOpenDay(day) }
                            )
                            .frame(maxWidth: .infinity)
                            Divider()
                        }
                    }
                    .padding(.vertical, 6)
                }
                .onAppear { proxy.scrollTo(7, anchor: .top) }
            }
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button("Previous Week", systemImage: "chevron.left") { onChangeWeek(weekStart.adding(days: -7)) }
                    .keyboardShortcut("[", modifiers: .command)
                Button("This Week") { onChangeWeek(today.startOfWeek()) }
                    .disabled(weekStart == today.startOfWeek())
                    .keyboardShortcut("t", modifiers: .command)
                Button("Next Week", systemImage: "chevron.right") { onChangeWeek(weekStart.adding(days: 7)) }
                    .keyboardShortcut("]", modifiers: .command)
            }
        }
    }

    private var title: String {
        let first = days[0].start(in: calendar), last = days[6].start(in: calendar)
        return "\(first.formatted(.dateTime.day().month(.abbreviated))) – \(last.formatted(.dateTime.day().month(.abbreviated).year()))"
    }

    private func energy(on day: LocalDay) -> Int? {
        checkIns.first { $0.dayKey == day.key }?.energy
    }
}

private struct DayHeader: View {
    let day: LocalDay
    let isToday: Bool
    let energy: Int?
    let allDay: [String]

    var body: some View {
        let date = day.start()
        VStack(spacing: 2) {
            Text(date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(date.formatted(.dateTime.day()))
                .font(.title3.weight(isToday ? .bold : .regular).monospacedDigit())
                .foregroundStyle(isToday ? Color.white : Color.primary)
                .frame(width: 30, height: 30)
                .background(isToday ? Color.accentColor : .clear, in: Circle())
            Label(energy.map { "\($0)" } ?? "–", systemImage: "bolt.fill")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(energy == nil ? .tertiary : .secondary)
                .help(energy.map { "Energy \($0)/5" } ?? "No check-in")
            if !allDay.isEmpty {
                Text(allDay.count == 1 ? allDay[0] : "\(allDay.count) all-day")
                    .font(.caption2)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
                    .background(Color.blue.opacity(0.18), in: Capsule())
                    .help(allDay.joined(separator: "\n"))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(date.formatted(date: .complete, time: .omitted))\(energy.map { ", energy \($0) of 5" } ?? "")")
    }
}

private struct HourLabels: View {
    let calendar: Calendar
    let day: LocalDay

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                Text(calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day.start(in: calendar))!
                        .formatted(date: .omitted, time: .shortened))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 4)
                    .offset(y: -6)
                    .opacity(hour == 0 ? 0 : 1)
                    .frame(height: WeekView.hourHeight, alignment: .top)
                    .id(hour)
            }
        }
    }
}

private struct DayColumn: View {
    let day: LocalDay
    let isToday: Bool
    let events: [CalendarEvent]
    let calendar: Calendar
    let onOpen: () -> Void

    var body: some View {
        let dayStart = day.start(in: calendar)
        let dayEnd = day.end(in: calendar)
        let hours = dayEnd.timeIntervalSince(dayStart) / 3600
        func y(_ date: Date) -> CGFloat {
            CGFloat(min(max(date, dayStart), dayEnd).timeIntervalSince(dayStart) / 3600) * WeekView.hourHeight
        }

        return GeometryReader { geo in
            let slots = TimelineLayout.slots(for: events.map { (id: $0.id, start: $0.start, end: $0.end) })
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    ForEach(0..<Int(hours.rounded()), id: \.self) { _ in
                        VStack { Divider() }.frame(height: WeekView.hourHeight, alignment: .top)
                    }
                }
                .background(isToday ? Color.accentColor.opacity(0.04) : .clear)
                .contentShape(Rectangle())
                .onTapGesture(perform: onOpen)

                ForEach(events) { event in
                    let slot = slots[event.id] ?? .init(column: 0, columnCount: 1)
                    let width = (geo.size.width - 4) / CGFloat(slot.columnCount)
                    WeekBlock(event: event, height: max(y(event.end) - y(event.start), 10))
                        .frame(width: width - 1)
                        .offset(x: 2 + width * CGFloat(slot.column), y: y(event.start))
                        .onTapGesture(perform: onOpen)
                }
            }
        }
        .frame(height: CGFloat(hours) * WeekView.hourHeight)
    }
}

private struct WeekBlock: View {
    let event: CalendarEvent
    let height: CGFloat

    var body: some View {
        let isPast = event.end < .now
        HStack(alignment: .top, spacing: 2) {
            if event.kind == .taskBlock, event.isLocked {
                Image(systemName: "pin.fill").font(.system(size: 8))
            }
            Text(event.title)
                .font(.caption2.weight(.medium))
                .lineLimit(height > 26 ? 2 : 1)
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 1)
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
        .background(event.kind.tint.opacity(0.25), in: RoundedRectangle(cornerRadius: 4))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1).fill(event.kind.tint).frame(width: 2)
        }
        .opacity(isPast ? 0.45 : 1)
        .help("\(event.title)\n\(event.start.formatted(date: .omitted, time: .shortened)) – \(event.end.formatted(date: .omitted, time: .shortened))")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(event.title), \(event.start.formatted(date: .omitted, time: .shortened)) to \(event.end.formatted(date: .omitted, time: .shortened))\(isPast ? ", past" : "")")
        .accessibilityAddTraits(.isButton)
    }
}
