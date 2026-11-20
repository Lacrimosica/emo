import EmoKit
import SwiftData
import SwiftUI

/// One day on iPhone: check-in, all-day strip, Plan Day and the touch timeline.
struct PhoneTodayView: View {
    let day: LocalDay
    let today: LocalDay
    let onChangeDay: (LocalDay) -> Void
    let onCheckIn: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query private var checkIns: [CheckIn]
    @Query private var dayEvents: [CalendarEvent]
    /// Set when "Plan Day" had to ask for a check-in first; planning resumes once it's saved.
    @State private var planMessage: String?
    @State private var isAddingTransit = false
    @State private var isConfirmingUnscheduleAll = false
    @State private var newEvent: CalendarEvent?

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
            header
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 8)

            if !allDayEvents.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Text("All day").font(.caption).foregroundStyle(.secondary)
                        ForEach(allDayEvents) { event in
                            Label(event.title, systemImage: event.origin == .linked ? "link" : "sun.max")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(event.kind.tint.opacity(0.2), in: Capsule())
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 8)
            }

            if pinnedConflictCount > 0 {
                Label(DayScreen.pinnedConflictMessage(count: pinnedConflictCount), systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            if let planMessage {
                Label(planMessage, systemImage: "wand.and.stars")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .transition(.opacity)
                    .onTapGesture { withAnimation { self.planMessage = nil } }
            }

            Divider()

            PhoneDayTimelineView(day: day)
        }
        .navigationTitle(day == today ? "Today" : day.start().formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Today") { onChangeDay(today) }
                    .disabled(day == today)
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Plan Day", systemImage: "wand.and.stars", action: planDay)
                Menu {
                    Button("New Event", systemImage: "calendar.badge.plus", action: addEvent)
                    Button("Add Transit…", systemImage: "car") { isAddingTransit = true }
                    Divider()
                    Button("Unschedule All", systemImage: "calendar.badge.minus", role: .destructive) {
                        isConfirmingUnscheduleAll = true
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                } primaryAction: {
                    addEvent()
                }
            }
        }
        .sheet(isPresented: $isAddingTransit) {
            NavigationStack { TransitSheet(day: day, today: today) }
        }
        .sheet(item: $newEvent) { event in
            NavigationStack { EventEditor(event: event, isNew: true) }
        }
        .confirmationDialog("Unschedule all tasks?", isPresented: $isConfirmingUnscheduleAll, titleVisibility: .visible) {
            Button("Unschedule All", role: .destructive) {
                let message = DayScreen.unscheduleAll(context: modelContext)
                withAnimation { planMessage = message }
            }
        } message: {
            Text("Removes every upcoming task block on every day, pinned ones included. Calendar events and past blocks stay.")
        }
        .onChange(of: day) {
            planMessage = nil
        }
        .task(id: planMessage) {
            guard planMessage != nil else { return }
            try? await Task.sleep(for: .seconds(8))
            withAnimation { planMessage = nil }
        }
    }

    /// Date with previous/next buttons (swipe left or right on it too) and the check-in.
    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Button("Previous Day", systemImage: "chevron.left") { onChangeDay(day.adding(days: -1)) }
                .labelStyle(.iconOnly)
            VStack(alignment: .leading, spacing: 1) {
                Text(day.start().formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.headline)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .minimumScaleFactor(0.8)
                if day != today {
                    Text(day < today ? "Past day" : "Upcoming")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Button("Next Day", systemImage: "chevron.right") { onChangeDay(day.adding(days: 1)) }
                .labelStyle(.iconOnly)
            Spacer(minLength: 4)
            PhoneCheckInButton(checkIn: checkIns.first, onCheckIn: onCheckIn)
        }
        .buttonStyle(.borderless)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    let dx = value.translation.width
                    guard abs(dx) > 60, abs(dx) > abs(value.translation.height) * 2 else { return }
                    onChangeDay(day.adding(days: dx < 0 ? 1 : -1))
                }
        )
        .sensoryFeedback(.selection, trigger: day)
    }

    private var allDayEvents: [CalendarEvent] { dayEvents.filter(\.isAllDay) }

    private var pinnedConflictCount: Int { DayScreen.pinnedConflictCount(in: dayEvents) }

    private func planDay() {
        let message = DayScreen.plan(day, hasCheckIn: !checkIns.isEmpty, context: modelContext)
        withAnimation { planMessage = message }
    }

    /// Creates a one-hour event and opens it; cancelling the editor removes it again.
    private func addEvent() {
        let start = DayScreen.newEventStart(on: day, today: today)
        newEvent = try? CalendarEngine(context: modelContext)
            .createFixedEvent(title: "New Event", start: start, end: start.addingTimeInterval(3600))
    }
}

private struct PhoneCheckInButton: View {
    let checkIn: CheckIn?
    let onCheckIn: () -> Void

    var body: some View {
        if let checkIn {
            Button(action: onCheckIn) {
                HStack(spacing: 10) {
                    Label("\(checkIn.mood)", systemImage: "face.smiling")
                    Label("\(checkIn.energy)", systemImage: "bolt.fill")
                }
                .font(.footnote.monospacedDigit())
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Mood \(checkIn.mood) of 5, energy \(checkIn.energy) of 5. Edit check-in.")
        } else {
            Button("Check In", systemImage: "sun.max", action: onCheckIn)
                .font(.footnote)
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
        PhoneTodayView(day: .today(), today: .today(), onChangeDay: { _ in }, onCheckIn: {})
    }
    .modelContainer(container)
}
