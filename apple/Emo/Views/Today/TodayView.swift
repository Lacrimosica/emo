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
    /// Set when "Plan Day" had to ask for a check-in first; planning resumes once it's saved.
    @State private var planAfterCheckIn = false
    @State private var planMessage: String?
    @State private var isAddingTransit = false

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
            }
        }
        .sheet(isPresented: $isAddingTransit) { TransitSheet(day: day, today: today) }
        .onChange(of: day) {
            selectedEventID = nil
            editingEventID = nil
            planAfterCheckIn = false
            planMessage = nil
        }
        .onChange(of: checkIns.first?.energy) { _, energy in
            if planAfterCheckIn, energy != nil {
                planAfterCheckIn = false
                planDay()
            }
        }
        .task(id: planMessage) {
            guard planMessage != nil else { return }
            try? await Task.sleep(for: .seconds(8))
            withAnimation { planMessage = nil }
        }
    }

    private func planDay() {
        // Today's plan is sized by today's energy, so ask first. Other days fall back to the default.
        if day == today, checkIns.isEmpty {
            planAfterCheckIn = true
            onCheckIn()
            return
        }
        do {
            if try Backlog(context: modelContext).openTasks().isEmpty {
                withAnimation { planMessage = "Your backlog is empty. Add some tasks, then plan." }
                return
            }
            let summary = try DayPlanning(context: modelContext).plan(day)
            withAnimation { planMessage = Self.describe(summary, assumedEnergy: checkIns.isEmpty) }
        } catch {
            planMessage = "Couldn't plan the day: \(error.localizedDescription)"
        }
    }

    static func describe(_ s: DayPlanning.Summary, assumedEnergy: Bool) -> String {
        var parts: [String] = []
        if s.planned.planned == 0, s.spill.planned == 0, s.unplacedTaskCount == 0 {
            parts.append("Everything in your backlog is already planned.")
        } else if s.planned.planned > 0 {
            parts.append("Planned \((s.planned.planned / 3600).hoursLabel) across \(s.planned.taskCount) task\(s.planned.taskCount == 1 ? "" : "s").")
        } else {
            parts.append(s.planned.day == LocalDay.today() ? "Nothing more fits today." : "Nothing fits on this day.")
        }
        if s.spill.planned > 0 {
            parts.append("\((s.spill.planned / 3600).hoursLabel) moved to \(s.spill.day.start().formatted(.dateTime.weekday(.wide))).")
        }
        if s.unplacedTaskCount > 0 {
            parts.append("\(s.unplacedTaskCount) task\(s.unplacedTaskCount == 1 ? "" : "s") still in the backlog.")
        }
        if assumedEnergy { parts.append("No check-in for this day, so medium energy was assumed.") }
        return parts.joined(separator: " ")
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
