import EmoKit
import SwiftData
import SwiftUI

/// The day timeline on iPhone, touch-first.
///
/// Tap a block to edit it in a sheet. Long-press a block to select it, and keep holding to drag it
/// to a new time (15-minute steps). A selected block shows resize handles on its top and bottom
/// edges and an actions menu. Tap an empty slot to add an event there. All writes go through
/// `CalendarEngine`.
struct PhoneDayTimelineView: View {
    let day: LocalDay

    @Environment(\.modelContext) private var modelContext
    @Query private var events: [CalendarEvent]
    @State private var selectedEventID: UUID?
    @State private var editing: EditTarget?
    @State private var editingTask: TaskItem?
    @State private var isDragging = false

    static let hourHeight: CGFloat = 60
    static let labelWidth: CGFloat = 50
    static let snapMinutes = 15
    static var snapHeight: CGFloat { hourHeight * CGFloat(snapMinutes) / 60 }

    private let calendar = Calendar.current

    struct EditTarget: Identifiable {
        let event: CalendarEvent
        let isNew: Bool
        var id: UUID { event.id }
    }

    init(day: LocalDay) {
        self.day = day
        self._events = Query(CalendarEngine.descriptor(for: day))
    }

    private var dayStart: Date { day.start(in: calendar) }
    private var dayEnd: Date { day.end(in: calendar) }
    private var totalHeight: CGFloat { y(for: dayEnd) }

    private func y(for date: Date) -> CGFloat {
        let clamped = min(max(date, dayStart), dayEnd)
        return CGFloat(clamped.timeIntervalSince(dayStart) / 3600) * Self.hourHeight
    }

    private func date(forY y: CGFloat) -> Date {
        dayStart.addingTimeInterval(TimeInterval(y / Self.hourHeight) * 3600)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                GeometryReader { geo in
                    let columnsWidth = geo.size.width - Self.labelWidth - 8
                    ZStack(alignment: .topLeading) {
                        PhoneHourGrid(dayStart: dayStart, dayEnd: dayEnd, calendar: calendar)
                            .contentShape(Rectangle())
                            .onTapGesture(coordinateSpace: .local) { location in
                                tapEmptySpace(atY: location.y)
                            }

                        let slots = TimelineLayout.slots(for: timedEvents.map { (id: $0.id, start: $0.start, end: $0.end) })
                        ForEach(timedEvents) { event in
                            let slot = slots[event.id] ?? .init(column: 0, columnCount: 1)
                            let width = columnsWidth / CGFloat(slot.columnCount)
                            PhoneEventBlock(
                                event: event,
                                frame: CGRect(
                                    x: Self.labelWidth + width * CGFloat(slot.column),
                                    y: y(for: event.start),
                                    width: width - 2,
                                    height: max(y(for: event.end) - y(for: event.start), 16)
                                ),
                                isSelected: selectedEventID == event.id,
                                onEdit: { selectedEventID = nil; editing = EditTarget(event: event, isNew: false) },
                                onLift: { selectedEventID = event.id },
                                onDraggingChanged: { isDragging = $0 },
                                onMove: { delta in move(event, by: delta) },
                                onResize: { edge, delta in resize(event, edge: edge, by: delta) }
                            ) {
                                menu(for: event)
                            }
                            .zIndex(selectedEventID == event.id ? 1 : 0)
                        }

                        if day == LocalDay.today(calendar: calendar) {
                            PhoneNowIndicator(y: y(for:))
                        }
                    }
                }
                .frame(height: totalHeight)
                .padding(.vertical, 10)
            }
            .scrollDisabled(isDragging)
            .onAppear { proxy.scrollTo(initialScrollHour(), anchor: .top) }
            .onChange(of: day) {
                selectedEventID = nil
                proxy.scrollTo(initialScrollHour(), anchor: .top)
            }
        }
        .sheet(item: $editing) { target in
            NavigationStack { EventEditor(event: target.event, isNew: target.isNew) }
        }
        .sheet(item: $editingTask) { task in
            NavigationStack { TaskEditorSheet(task: task) }
        }
    }

    @ViewBuilder
    private func menu(for event: CalendarEvent) -> some View {
        if event.kind == .taskBlock, event.isUserEditable {
            TaskBlockActions.menu(for: event, context: modelContext) { editingTask = $0 }
        } else if event.isUserEditable {
            Button("Edit…", systemImage: "pencil") { editing = EditTarget(event: event, isNew: false) }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { try? engine.delete(event) }
        }
    }

    /// All-day events are shown in a strip above the timeline (PhoneTodayView), not as 24-hour blocks.
    private var timedEvents: [CalendarEvent] { events.filter { !$0.isAllDay } }

    private func initialScrollHour() -> Int {
        let isToday = day == LocalDay.today(calendar: calendar)
        let hour = isToday ? calendar.component(.hour, from: .now) - 1 : 8
        return min(max(hour, 0), 23)
    }

    // MARK: Engine calls

    private var engine: CalendarEngine { CalendarEngine(context: modelContext) }

    /// The first tap on empty space only clears a selection; otherwise it adds an event there.
    private func tapEmptySpace(atY y: CGFloat) {
        if selectedEventID != nil {
            selectedEventID = nil
            return
        }
        let start = date(forY: y).snapped(toMinutes: Self.snapMinutes, calendar: calendar)
        let end = min(start.addingTimeInterval(3600), dayEnd)
        guard let event = try? engine.createFixedEvent(title: "New Event", start: start, end: end) else { return }
        editing = EditTarget(event: event, isNew: true)
    }

    private func move(_ event: CalendarEvent, by delta: TimeInterval) {
        let newStart = event.start.addingTimeInterval(delta).snapped(toMinutes: Self.snapMinutes, calendar: calendar)
        try? engine.move(event, to: newStart)
    }

    private func resize(_ event: CalendarEvent, edge: TimelineEdge, by delta: TimeInterval) {
        switch edge {
        case .top:
            let newStart = event.start.addingTimeInterval(delta).snapped(toMinutes: Self.snapMinutes, calendar: calendar)
            try? engine.update(event, start: newStart)
        case .bottom:
            let newEnd = event.end.addingTimeInterval(delta).snapped(toMinutes: Self.snapMinutes, calendar: calendar)
            try? engine.update(event, end: newEnd)
        }
    }
}

// MARK: - Pieces

private struct PhoneHourGrid: View {
    let dayStart: Date
    let dayEnd: Date
    let calendar: Calendar

    var body: some View {
        let hours = Int((dayEnd.timeIntervalSince(dayStart) / 3600).rounded())
        VStack(spacing: 0) {
            ForEach(0..<hours, id: \.self) { i in
                let hourDate = calendar.date(byAdding: .hour, value: i, to: dayStart)!
                HStack(alignment: .top, spacing: 6) {
                    Text(hourDate.formatted(date: .omitted, time: .shortened))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: PhoneDayTimelineView.labelWidth - 6, alignment: .trailing)
                        .offset(y: -6)
                        .opacity(i == 0 ? 0 : 1)
                    VStack { Divider() }
                }
                .frame(height: PhoneDayTimelineView.hourHeight, alignment: .top)
                .id(i)
            }
        }
    }
}

private struct PhoneNowIndicator: View {
    let y: (Date) -> CGFloat

    var body: some View {
        TimelineView(.everyMinute) { context in
            HStack(spacing: 0) {
                Circle().fill(.red).frame(width: 8, height: 8)
                Rectangle().fill(.red).frame(height: 1.5)
            }
            .padding(.leading, PhoneDayTimelineView.labelWidth - 4)
            .offset(y: y(context.date) - 4)
            .allowsHitTesting(false)
        }
    }
}

enum TimelineEdge { case top, bottom }

/// One block on the phone timeline. Offsets while dragging snap to 15-minute steps so the block
/// lands where it is shown.
struct PhoneEventBlock<Actions: View>: View {
    let event: CalendarEvent
    let frame: CGRect
    let isSelected: Bool
    let onEdit: () -> Void
    /// The long press finished: the block is picked up and selected.
    let onLift: () -> Void
    let onDraggingChanged: (Bool) -> Void
    let onMove: (TimeInterval) -> Void
    let onResize: (TimelineEdge, TimeInterval) -> Void
    @ViewBuilder let actions: () -> Actions

    private enum Press: Equatable {
        case idle
        case pressing
        case dragging(CGFloat)

        var translation: CGFloat { if case .dragging(let dy) = self { dy } else { 0 } }
        var isLifted: Bool { if case .dragging = self { true } else { false } }
    }

    @GestureState private var press: Press = .idle
    @GestureState private var topOffset: CGFloat = 0
    @GestureState private var bottomOffset: CGFloat = 0

    private static func snapped(_ dy: CGFloat) -> CGFloat {
        (dy / PhoneDayTimelineView.snapHeight).rounded() * PhoneDayTimelineView.snapHeight
    }

    private static func seconds(for dy: CGFloat) -> TimeInterval {
        TimeInterval(snapped(dy) / PhoneDayTimelineView.hourHeight) * 3600
    }

    private var editable: Bool { event.isUserEditable }
    private var isInteracting: Bool { press != .idle || topOffset != 0 || bottomOffset != 0 }

    var body: some View {
        let top = Self.snapped(topOffset)
        let height = max(frame.height - top + Self.snapped(bottomOffset), 16)
        let lifted = press.isLifted
        let moveOffset = Self.snapped(press.translation)

        content(height: height)
            .frame(width: frame.width, height: height, alignment: .topLeading)
            .background(event.kind.tint.opacity(isSelected || lifted ? 0.45 : 0.25), in: RoundedRectangle(cornerRadius: 6))
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(event.kind.tint).frame(width: 3).padding(.vertical, 2)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isSelected ? event.kind.tint : .clear, lineWidth: 1.5)
            }
            .overlay(alignment: .topTrailing) {
                if editable, !lifted {
                    HStack(spacing: 0) {
                        if showsQuickActions(height: height) { BlockQuickActions(event: event) }
                        if isSelected { actionsButton(height: height) }
                    }
                    .padding(.top, 3)
                    .padding(.trailing, isSelected ? 0 : 3)
                }
            }
            .overlay(alignment: .top) { if isSelected, editable, !lifted { resizeHandle(.top) } }
            .overlay(alignment: .bottom) { if isSelected, editable, !lifted { resizeHandle(.bottom) } }
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .scaleEffect(lifted ? 1.02 : 1)
            .shadow(color: .black.opacity(lifted ? 0.2 : 0), radius: 6, y: 3)
            .onTapGesture(perform: onEdit)
            .gesture(moveGesture, isEnabled: editable)
            .offset(x: frame.minX, y: frame.minY + moveOffset + top)
            .animation(.snappy(duration: 0.15), value: moveOffset)
            .sensoryFeedback(.impact(weight: .medium), trigger: lifted) { _, new in new }
            .sensoryFeedback(.selection, trigger: moveOffset)
            .onChange(of: isInteracting) { _, interacting in onDraggingChanged(interacting) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(event.title)\(event.kind == .taskBlock && event.isLocked ? ", pinned" : ""), \(event.start.formatted(date: .omitted, time: .shortened)) to \(event.end.formatted(date: .omitted, time: .shortened))")
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityHint(editable ? "Opens the event. Long-press and drag to move." : "From Calendar; read-only")
            .accessibilityAction(named: "Move 15 minutes later") { onMove(15 * 60) }
            .accessibilityAction(named: "Move 15 minutes earlier") { onMove(-15 * 60) }
    }

    private func content(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                if event.kind == .taskBlock, event.isLocked {
                    Image(systemName: "pin.fill").font(.caption2).accessibilityHidden(true)
                }
                if event.origin == .linked {
                    Image(systemName: "link").font(.caption2).accessibilityHidden(true)
                }
                Text(event.title)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(height > 40 ? 2 : 1)
            }
            if height > 40 {
                Text("\(event.start.formatted(date: .omitted, time: .shortened)) – \(event.end.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2.monospacedDigit())
                    .opacity(0.8)
            }
        }
        .padding(.leading, 7)
        .padding(.trailing, trailingInset(height: height))
        .padding(.vertical, 2)
    }

    /// Quick-action icons show on any block with room for them.
    private func showsQuickActions(height: CGFloat) -> Bool {
        editable && height >= BlockQuickActions.buttonSize + 6
            && frame.width >= BlockQuickActions.width(for: event) + 90
    }

    /// Keeps the title clear of the icons drawn over the block's top-right corner.
    private func trailingInset(height: CGFloat) -> CGFloat {
        (showsQuickActions(height: height) ? BlockQuickActions.width(for: event) + 3 : 4) + (isSelected ? 30 : 0)
    }

    /// Long-press to pick the block up, then drag without lifting the finger.
    private var moveGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .updating($press) { value, state, _ in
                switch value {
                case .first(true): state = .pressing
                case .second(true, let drag): state = .dragging(drag?.translation.height ?? 0)
                default: state = .idle
                }
            }
            .onChanged { value in
                if case .second(true, nil) = value, !isSelected { onLift() }
            }
            .onEnded { value in
                guard case .second(true, let drag?) = value else { return }
                let seconds = Self.seconds(for: drag.translation.height)
                if seconds != 0 { onMove(seconds) }
            }
    }

    private func actionsButton(height: CGFloat) -> some View {
        Menu(content: actions) {
            Image(systemName: "ellipsis.circle.fill")
                .font(.body)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(event.kind.tint)
                .frame(width: 30, height: min(max(height, 16), 30))
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Actions")
    }

    /// A grab dot on the edge with a larger invisible touch area.
    private func resizeHandle(_ edge: TimelineEdge) -> some View {
        Circle()
            .fill(.background)
            .stroke(event.kind.tint, lineWidth: 2)
            .frame(width: 11, height: 11)
            .frame(width: 44, height: 24)
            .contentShape(Rectangle())
            .offset(y: edge == .top ? -12 : 12)
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .updating(edge == .top ? $topOffset : $bottomOffset) { value, state, _ in
                        state = value.translation.height
                    }
                    .onEnded { value in
                        let seconds = Self.seconds(for: value.translation.height)
                        if seconds != 0 { onResize(edge, seconds) }
                    }
            )
            .accessibilityHidden(true)
    }
}
