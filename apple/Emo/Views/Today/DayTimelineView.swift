import EmoKit
import SwiftData
import SwiftUI

/// A vertical 24-hour timeline for one local day, backed by the internal calendar.
///
/// Double-click empty space to create an event, click to select, double-click or Return to edit,
/// drag to move, drag the top/bottom edge to resize, Delete to remove. All writes go through
/// `CalendarEngine`.
struct DayTimelineView: View {
    let day: LocalDay
    @Binding var selectedEventID: UUID?
    @Binding var editingEventID: UUID?

    @Environment(\.modelContext) private var modelContext
    @Query private var events: [CalendarEvent]
    /// Keyboard focus, so Delete / Return / Escape reach the timeline after a click.
    @FocusState private var isFocused: Bool

    static let hourHeight: CGFloat = 56
    static let labelWidth: CGFloat = 52
    static let snapMinutes = 15

    private let calendar = Calendar.current

    init(day: LocalDay, selectedEventID: Binding<UUID?>, editingEventID: Binding<UUID?>) {
        self.day = day
        self._selectedEventID = selectedEventID
        self._editingEventID = editingEventID
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
                        HourGrid(dayStart: dayStart, dayEnd: dayEnd, calendar: calendar)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2, coordinateSpace: .local) { location in
                                createEvent(atY: location.y)
                            }
                            .onTapGesture { selectedEventID = nil; isFocused = true }

                        let slots = TimelineLayout.slots(for: events.map { (id: $0.id, start: $0.start, end: $0.end) })
                        ForEach(events) { event in
                            let slot = slots[event.id] ?? .init(column: 0, columnCount: 1)
                            let width = columnsWidth / CGFloat(slot.columnCount)
                            EventBlock(
                                event: event,
                                frame: CGRect(
                                    x: Self.labelWidth + width * CGFloat(slot.column),
                                    y: y(for: event.start),
                                    width: width - 2,
                                    height: max(y(for: event.end) - y(for: event.start), 14)
                                ),
                                isSelected: selectedEventID == event.id,
                                isEditing: editingBinding(for: event),
                                onSelect: { selectedEventID = event.id; isFocused = true },
                                onEdit: { editingEventID = event.id },
                                onMove: { delta in move(event, by: delta) },
                                onResize: { edge, delta in resize(event, edge: edge, by: delta) }
                            )
                        }

                        if day == LocalDay.today(calendar: calendar) {
                            NowIndicator(y: y(for:))
                        }
                    }
                }
                .frame(height: totalHeight)
                .padding(.vertical, 8)
            }
            .onAppear { proxy.scrollTo(initialScrollHour(), anchor: .top) }
            .onChange(of: day) { proxy.scrollTo(initialScrollHour(), anchor: .top) }
        }
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onDeleteCommand(perform: deleteSelected)
        .onKeyPress(.return) {
            guard let selectedEventID else { return .ignored }
            editingEventID = selectedEventID
            return .handled
        }
        .onKeyPress(.escape) {
            guard selectedEventID != nil else { return .ignored }
            selectedEventID = nil
            return .handled
        }
    }

    private func editingBinding(for event: CalendarEvent) -> Binding<Bool> {
        Binding(
            get: { editingEventID == event.id },
            set: { if !$0, editingEventID == event.id { editingEventID = nil } }
        )
    }

    private func initialScrollHour() -> Int {
        let isToday = day == LocalDay.today(calendar: calendar)
        let hour = isToday ? calendar.component(.hour, from: .now) - 1 : 8
        return min(max(hour, 0), 23)
    }

    // MARK: Engine calls

    private var engine: CalendarEngine { CalendarEngine(context: modelContext) }

    private func createEvent(atY y: CGFloat) {
        let start = date(forY: y).snapped(toMinutes: Self.snapMinutes, calendar: calendar)
        let end = min(start.addingTimeInterval(3600), dayEnd)
        guard let event = try? engine.createFixedEvent(title: "New Event", start: start, end: end) else { return }
        selectedEventID = event.id
        editingEventID = event.id
        isFocused = true
    }

    private func move(_ event: CalendarEvent, by delta: TimeInterval) {
        let newStart = event.start.addingTimeInterval(delta).snapped(toMinutes: Self.snapMinutes, calendar: calendar)
        try? engine.move(event, to: newStart)
    }

    private func resize(_ event: CalendarEvent, edge: EventBlock.Edge, by delta: TimeInterval) {
        switch edge {
        case .top:
            let newStart = event.start.addingTimeInterval(delta).snapped(toMinutes: Self.snapMinutes, calendar: calendar)
            try? engine.update(event, start: newStart)
        case .bottom:
            let newEnd = event.end.addingTimeInterval(delta).snapped(toMinutes: Self.snapMinutes, calendar: calendar)
            try? engine.update(event, end: newEnd)
        }
    }

    private func deleteSelected() {
        guard let id = selectedEventID, let event = events.first(where: { $0.id == id }) else { return }
        if (try? engine.delete(event)) != nil { selectedEventID = nil }
    }
}

// MARK: - Pieces

private struct HourGrid: View {
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
                        .frame(width: DayTimelineView.labelWidth - 6, alignment: .trailing)
                        .offset(y: -6)
                        .opacity(i == 0 ? 0 : 1)
                    VStack { Divider() }
                }
                .frame(height: DayTimelineView.hourHeight, alignment: .top)
                .id(i)
            }
        }
    }
}

private struct NowIndicator: View {
    let y: (Date) -> CGFloat

    var body: some View {
        TimelineView(.everyMinute) { context in
            HStack(spacing: 0) {
                Circle().fill(.red).frame(width: 8, height: 8)
                Rectangle().fill(.red).frame(height: 1.5)
            }
            .padding(.leading, DayTimelineView.labelWidth - 4)
            .offset(y: y(context.date) - 4)
            .allowsHitTesting(false)
        }
    }
}

struct EventBlock: View {
    enum Edge { case top, bottom }

    let event: CalendarEvent
    let frame: CGRect
    let isSelected: Bool
    @Binding var isEditing: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onMove: (TimeInterval) -> Void
    let onResize: (Edge, TimeInterval) -> Void

    @GestureState private var moveOffset: CGFloat = 0
    @GestureState private var topOffset: CGFloat = 0
    @GestureState private var bottomOffset: CGFloat = 0

    private static func seconds(for dy: CGFloat) -> TimeInterval {
        TimeInterval(dy / DayTimelineView.hourHeight) * 3600
    }

    var body: some View {
        let editable = event.isUserEditable
        let height = max(frame.height - topOffset + bottomOffset, 14)

        VStack(alignment: .leading, spacing: 1) {
            Text(event.title)
                .font(.callout.weight(.semibold))
                .lineLimit(height > 36 ? 2 : 1)
            if height > 36 {
                Text("\(event.start.formatted(date: .omitted, time: .shortened)) – \(event.end.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2.monospacedDigit())
                    .opacity(0.8)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .frame(width: frame.width, height: height, alignment: .topLeading)
        .background(event.kind.tint.opacity(isSelected ? 0.45 : 0.25), in: RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(event.kind.tint).frame(width: 3).padding(.vertical, 2)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isSelected ? event.kind.tint : .clear, lineWidth: 1.5)
        }
        .overlay(alignment: .top) { if editable { resizeHandle(.top) } }
        .overlay(alignment: .bottom) { if editable { resizeHandle(.bottom) } }
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .onTapGesture(count: 2) { onSelect(); onEdit() }
        .onTapGesture { onSelect() }
        .gesture(
            DragGesture(minimumDistance: 4)
                .updating($moveOffset) { value, state, _ in state = value.translation.height }
                .onEnded { value in onMove(Self.seconds(for: value.translation.height)) },
            isEnabled: editable
        )
        .popover(isPresented: $isEditing, arrowEdge: .trailing) {
            EventEditor(event: event)
        }
        .offset(x: frame.minX, y: frame.minY + moveOffset + topOffset)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(event.title), \(event.start.formatted(date: .omitted, time: .shortened)) to \(event.end.formatted(date: .omitted, time: .shortened))")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { onSelect(); onEdit() }
        .accessibilityHint(editable ? "Double-click to edit" : "From an integration; read-only")
    }

    private func resizeHandle(_ edge: Edge) -> some View {
        Color.clear
            .frame(height: 6)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .updating(edge == .top ? $topOffset : $bottomOffset) { value, state, _ in
                        state = value.translation.height
                    }
                    .onEnded { value in onResize(edge, Self.seconds(for: value.translation.height)) }
            )
    }
}

extension CalendarEventKind {
    var tint: Color {
        switch self {
        case .fixed: .blue
        case .taskBlock: .purple
        case .transit: .orange
        case .buffer: .gray
        }
    }
}
