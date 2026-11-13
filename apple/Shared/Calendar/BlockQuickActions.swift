import EmoKit
import SwiftData
import SwiftUI

/// Small icon buttons drawn on a block itself, so common actions don't need a menu: complete,
/// skip, pin and remove for task blocks; delete for other editable events.
struct BlockQuickActions: View {
    let event: CalendarEvent

    @Environment(\.modelContext) private var modelContext

    /// Width the buttons need, so callers can hide them on narrow blocks.
    static func width(for event: CalendarEvent) -> CGFloat {
        CGFloat(event.kind == .taskBlock ? 4 : 1) * (buttonSize + spacing)
    }

    static let buttonSize: CGFloat = 24
    static let spacing: CGFloat = 2

    var body: some View {
        HStack(spacing: Self.spacing) {
            if event.kind == .taskBlock {
                icon(TaskBlockActions.completeLabel(for: event, in: modelContext), "checkmark.circle") { perform(.completeTask) }
                icon("Skip for Today", "forward") { perform(.skipToday) }
                icon(event.isLocked ? "Unpin" : "Pin Here", event.isLocked ? "pin.slash" : "pin") { perform(.togglePin) }
                icon("Remove Block", "trash") { perform(.removeBlock) }
            } else {
                icon("Delete", "trash") { try? CalendarEngine(context: modelContext).delete(event) }
            }
        }
        .foregroundStyle(event.kind.tint)
    }

    private func icon(_ title: String, _ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .frame(width: Self.buttonSize, height: Self.buttonSize)
                .background(.background.opacity(0.7), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }

    private func perform(_ action: TaskBlockAction) {
        withAnimation { try? TaskBlockActions.perform(action, on: event, in: modelContext) }
    }
}
