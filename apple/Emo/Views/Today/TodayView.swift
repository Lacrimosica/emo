import EmoKit
import SwiftData
import SwiftUI

/// One day: its check-in and its timeline on the internal calendar.
struct TodayView: View {
    let day: LocalDay
    let today: LocalDay
    let onChangeDay: (LocalDay) -> Void
    let onCheckIn: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query private var checkIns: [CheckIn]
    @State private var selectedEventID: UUID?
    @State private var editingEventID: UUID?

    init(day: LocalDay, today: LocalDay, onChangeDay: @escaping (LocalDay) -> Void, onCheckIn: @escaping () -> Void) {
        self.day = day
        self.today = today
        self.onChangeDay = onChangeDay
        self.onCheckIn = onCheckIn
        self._checkIns = Query(CheckIns.descriptor(for: day))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(day.start().formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .font(.title.weight(.semibold))
                    if day != today {
                        Text(day < today ? "Past day" : "Upcoming")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                CheckInSummary(checkIn: checkIns.first, onCheckIn: onCheckIn)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            DayTimelineView(day: day, selectedEventID: $selectedEventID, editingEventID: $editingEventID)
        }
        .navigationTitle(day == today ? "Today" : day.start().formatted(date: .abbreviated, time: .omitted))
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button("Previous Day", systemImage: "chevron.left") { onChangeDay(day.adding(days: -1)) }
                    .keyboardShortcut("[", modifiers: .command)
                Button("Today") { onChangeDay(today) }
                    .disabled(day == today)
                    .keyboardShortcut("t", modifiers: .command)
                Button("Next Day", systemImage: "chevron.right") { onChangeDay(day.adding(days: 1)) }
                    .keyboardShortcut("]", modifiers: .command)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("New Event", systemImage: "calendar.badge.plus", action: newEvent)
                    .keyboardShortcut("e", modifiers: .command)
            }
        }
        .onChange(of: day) {
            selectedEventID = nil
            editingEventID = nil
        }
    }

    /// Creates a one-hour event at the next quarter hour today, or 9:00 on other days.
    private func newEvent() {
        let calendar = Calendar.current
        let start: Date
        if day == today {
            let next = Date.now.addingTimeInterval(7.5 * 60).snapped(toMinutes: 15, calendar: calendar)
            start = min(next, day.end(in: calendar).addingTimeInterval(-3600))
        } else {
            start = calendar.date(byAdding: .hour, value: 9, to: day.start(in: calendar))!
        }
        let engine = CalendarEngine(context: modelContext)
        guard let event = try? engine.createFixedEvent(title: "New Event", start: start, end: start.addingTimeInterval(3600))
        else { return }
        selectedEventID = event.id
        editingEventID = event.id
    }
}

private struct CheckInSummary: View {
    let checkIn: CheckIn?
    let onCheckIn: () -> Void

    var body: some View {
        if let checkIn {
            Button(action: onCheckIn) {
                HStack(spacing: 14) {
                    Label("\(checkIn.mood)/5", systemImage: "face.smiling")
                    Label("\(checkIn.energy)/5", systemImage: "bolt.fill")
                }
                .font(.callout.monospacedDigit())
            }
            .buttonStyle(.bordered)
            .help("Mood and energy — click to edit")
            .accessibilityLabel("Mood \(checkIn.mood) of 5, energy \(checkIn.energy) of 5. Edit check-in.")
        } else {
            Button("Check In", systemImage: "sun.max", action: onCheckIn)
                .buttonStyle(.borderedProminent)
        }
    }
}

#Preview {
    let container = try! EmoStore.makeContainer(.inMemory)
    let engine = CalendarEngine(context: container.mainContext)
    let start = Calendar.current.date(byAdding: .hour, value: 10, to: LocalDay.today().start())!
    try! engine.createFixedEvent(title: "Dentist", start: start, end: start.addingTimeInterval(3600))
    try! engine.createFixedEvent(title: "Call with Sam", start: start.addingTimeInterval(1800), end: start.addingTimeInterval(5400))
    try! CheckIns(context: container.mainContext).record(mood: 4, energy: 2, for: .today())
    return NavigationStack {
        TodayView(day: .today(), today: .today(), onChangeDay: { _ in }, onCheckIn: {})
    }
    .modelContainer(container)
    .frame(width: 700, height: 600)
}
