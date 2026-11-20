import EmoKit
import SwiftData
import SwiftUI

/// The week on iPhone as a 7-day agenda: one section per day with its events in time order.
/// Tapping a day or an event opens that day in Today.
struct PhoneWeekView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.modelContext) private var modelContext
    @State private var planMessage: String?
    let weekStart: LocalDay
    let today: LocalDay
    let onChangeWeek: (LocalDay) -> Void
    let onOpenDay: (LocalDay) -> Void

    @Query private var events: [CalendarEvent]
    @Query private var checkIns: [CheckIn]

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
        ScrollViewReader { proxy in
            List {
                ForEach(days, id: \.self) { day in
                    let dayEvents = events(on: day)
                    Section {
                        if dayEvents.isEmpty {
                            Button { onOpenDay(day) } label: {
                                Text("Nothing scheduled")
                            }
                            .foregroundStyle(.secondary)
                            .accessibilityHint("Opens this day")
                        } else {
                            ForEach(dayEvents) { event in
                                Button { onOpenDay(day) } label: {
                                    AgendaRow(event: event)
                                }
                                .foregroundStyle(.primary)
                                .accessibilityHint("Opens this day")
                            }
                        }
                    } header: {
                        Button { onOpenDay(day) } label: {
                            AgendaDayHeader(day: day, isToday: day == today, energy: energy(on: day),
                                            plannedHours: plannedHours(in: dayEvents))
                        }
                        .foregroundStyle(.primary)
                        .accessibilityHint("Opens this day")
                    }
                    .id(day)
                }
            }
            .listStyle(.insetGrouped)
            .onAppear { if days.contains(today) { proxy.scrollTo(today, anchor: .top) } }
        }
        .navigationTitle(title)
        .safeAreaInset(edge: .bottom) {
            if let planMessage {
                Label(planMessage, systemImage: "wand.and.stars")
                    .font(.callout)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                    .transition(.opacity)
            }
        }
        .onChange(of: weekStart) { planMessage = nil }
        .task(id: planMessage) {
            guard planMessage != nil else { return }
            try? await Task.sleep(for: .seconds(10))
            withAnimation { planMessage = nil }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("This Week") { onChangeWeek(today.startOfWeek()) }
                    .disabled(weekStart == today.startOfWeek())
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Plan Week", systemImage: "wand.and.stars") {
                    let message = DayScreen.planWeek(starting: weekStart, today: today, context: modelContext)
                    withAnimation { planMessage = message }
                }
                .disabled(weekStart.adding(days: 6) < today)
                Button("Previous Week", systemImage: "chevron.left") { onChangeWeek(weekStart.adding(days: -7)) }
                Button("Next Week", systemImage: "chevron.right") { onChangeWeek(weekStart.adding(days: 7)) }
            }
        }
    }

    private var title: String {
        let first = days[0].start(in: calendar), last = days[6].start(in: calendar)
        // At accessibility text sizes the full title gets cut off: "16–22 Nov" instead.
        if dynamicTypeSize.isAccessibilitySize, calendar.isDate(first, equalTo: last, toGranularity: .month) {
            return "\(first.formatted(.dateTime.day()))–\(last.formatted(.dateTime.day().month(.abbreviated)))"
        }
        return "\(first.formatted(.dateTime.day().month(.abbreviated))) – \(last.formatted(.dateTime.day().month(.abbreviated)))"
    }

    /// The day's events, all-day ones first, then by start time.
    private func events(on day: LocalDay) -> [CalendarEvent] {
        let start = day.start(in: calendar), end = day.end(in: calendar)
        return events
            .filter { $0.start < end && $0.end > start }
            .sorted { ($0.isAllDay ? 0 : 1, $0.start) < ($1.isAllDay ? 0 : 1, $1.start) }
    }

    private func plannedHours(in dayEvents: [CalendarEvent]) -> Double {
        dayEvents.filter { $0.kind == .taskBlock }.reduce(0) { $0 + $1.duration } / 3600
    }

    private func energy(on day: LocalDay) -> Int? {
        checkIns.first { $0.dayKey == day.key }?.energy
    }
}

private struct AgendaDayHeader: View {
    let day: LocalDay
    let isToday: Bool
    let energy: Int?
    let plannedHours: Double

    var body: some View {
        let date = day.start()
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
                .font(.headline)
                .foregroundStyle(isToday ? Color.accentColor : .primary)
            if isToday {
                Text("Today")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.accentColor, in: Capsule())
                    .foregroundStyle(.white)
            }
            Spacer()
            if plannedHours > 0 {
                Label(plannedHours.hoursLabel, systemImage: "checklist")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if let energy {
                Label("\(energy)", systemImage: "bolt.fill")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .textCase(nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(date))
        .accessibilityAddTraits(.isHeader)
    }

    private func accessibilityText(_ date: Date) -> String {
        var parts = [date.formatted(date: .complete, time: .omitted)]
        if isToday { parts.append("today") }
        if plannedHours > 0 { parts.append("\(plannedHours.hoursLabel) of tasks planned") }
        if let energy { parts.append("energy \(energy) of 5") }
        return parts.joined(separator: ", ")
    }
}

private struct AgendaRow: View {
    let event: CalendarEvent

    var body: some View {
        let isPast = event.end < .now
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(event.kind.tint)
                .frame(width: 4)
                .frame(maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if event.kind == .taskBlock, event.isLocked {
                        Image(systemName: "pin.fill").font(.caption2).accessibilityHidden(true)
                    }
                    if event.origin == .linked {
                        Image(systemName: "link").font(.caption2).accessibilityHidden(true)
                    }
                    Text(event.title).lineLimit(2)
                }
                Text(timeText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .opacity(isPast ? 0.5 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(event.title), \(timeText)\(event.kind == .taskBlock && event.isLocked ? ", pinned" : "")\(isPast ? ", past" : "")")
    }

    private var timeText: String {
        if event.isAllDay { return "All day" }
        return "\(event.start.formatted(date: .omitted, time: .shortened)) – \(event.end.formatted(date: .omitted, time: .shortened))"
    }
}

#Preview {
    let container = try! EmoStore.makeContainer(.inMemory)
    let engine = CalendarEngine(context: container.mainContext)
    let start = Calendar.current.date(byAdding: .hour, value: 10, to: LocalDay.today().start())!
    try! engine.createFixedEvent(title: "Dentist", start: start, end: start.addingTimeInterval(3600))
    return NavigationStack {
        PhoneWeekView(weekStart: LocalDay.today().startOfWeek(), today: .today(), onChangeWeek: { _ in }, onOpenDay: { _ in })
    }
    .modelContainer(container)
}
