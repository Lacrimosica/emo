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
    @Query private var dayEvents: [CalendarEvent]
    @State private var selectedEventID: UUID?
    @State private var editingEventID: UUID?
    /// Set when "Plan Day" had to ask for a check-in first; planning resumes once it's saved.
    @State private var planMessage: String?
    @State private var isAddingTransit = false
    @State private var isConfirmingUnscheduleAll = false

    init(day: LocalDay, today: LocalDay, onChangeDay: @escaping (LocalDay) -> Void, onCheckIn: @escaping () -> Void) {
        self.day = day
        self.today = today
        self.onChangeDay = onChangeDay
        self.onCheckIn = onCheckIn
        self._checkIns = Query(CheckIns.descriptor(for: day))
        self._dayEvents = Query(CalendarEngine.descriptor(for: day))
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

            if !allDayEvents.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Text("All day").font(.caption).foregroundStyle(.secondary)
                        ForEach(allDayEvents) { event in
                            Label(event.title, systemImage: event.origin == .linked ? "link" : "sun.max")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(event.kind.tint.opacity(0.2), in: Capsule())
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 8)
            }

            if pinnedConflictCount > 0 {
                Label(DayScreen.pinnedConflictMessage(count: pinnedConflictCount),
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }

            if let planMessage {
                Label(planMessage, systemImage: "wand.and.stars")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
                    .transition(.opacity)
            }

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
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Button("Event", systemImage: "calendar", action: newEvent)
                    Button("Transit…", systemImage: "car") { isAddingTransit = true }
                } label: {
                    Label("New Event", systemImage: "calendar.badge.plus")
                } primaryAction: {
                    newEvent()
                }
                .keyboardShortcut("e", modifiers: .command)
                .help("New event (⌘E); hold for transit")
                Button("Plan Day", systemImage: "wand.and.stars", action: planDay)
                    .keyboardShortcut("r", modifiers: .command)
                    .help("Fill free time with backlog tasks (⌘R)")
                Button("Unschedule All", systemImage: "calendar.badge.minus") { isConfirmingUnscheduleAll = true }
                    .help("Remove every upcoming task block, pinned ones included")
            }
        }
        .sheet(isPresented: $isAddingTransit) { TransitSheet(day: day, today: today) }
        .confirmationDialog("Unschedule all tasks?", isPresented: $isConfirmingUnscheduleAll) {
            Button("Unschedule All", role: .destructive, action: unscheduleAll)
        } message: {
            Text("Removes every upcoming task block on every day, pinned ones included. Calendar events and past blocks stay.")
        }
        .onChange(of: day) {
            selectedEventID = nil
            editingEventID = nil
            planMessage = nil
        }
        .task(id: planMessage) {
            guard planMessage != nil else { return }
            try? await Task.sleep(for: .seconds(8))
            withAnimation { planMessage = nil }
        }
    }

    private func planDay() {
        let message = DayScreen.plan(day, hasCheckIn: !checkIns.isEmpty, context: modelContext)
        withAnimation { planMessage = message }
    }

    private func unscheduleAll() {
        let message = DayScreen.unscheduleAll(context: modelContext)
        withAnimation { planMessage = message }
    }

    private var allDayEvents: [CalendarEvent] { dayEvents.filter(\.isAllDay) }

    private var pinnedConflictCount: Int { DayScreen.pinnedConflictCount(in: dayEvents) }

    /// Creates a one-hour event at the next quarter hour today, or 9:00 on other days.
    private func newEvent() {
        let start = DayScreen.newEventStart(on: day, today: today)
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
