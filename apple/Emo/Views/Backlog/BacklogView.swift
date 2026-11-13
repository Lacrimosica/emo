import EmoKit
import SwiftData
import SwiftUI

struct BacklogView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(Backlog.openTasksDescriptor) private var tasks: [TaskItem]

    @State private var editor: EditorTarget?
    @State private var isChatting = false
    @State private var pinning: TaskItem?
    @State private var deleting: TaskItem?
    @State private var errorMessage: String?

    /// Which task the editor sheet is for; `.new` creates one.
    enum EditorTarget: Identifiable {
        case new
        case edit(TaskItem)
        var id: String {
            switch self {
            case .new: "new"
            case .edit(let task): task.id.uuidString
            }
        }
    }

    var body: some View {
        Group {
            if tasks.isEmpty {
                ContentUnavailableView {
                    Label("No Tasks", systemImage: "tray")
                } description: {
                    Text("Add a task to start filling your backlog.")
                } actions: {
                    Button("Add Task") { editor = .new }
                }
            } else {
                List(tasks) { task in
                    TaskRow(task: task, today: .today()) { complete(task) }
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { editor = .edit(task) }
                        .contextMenu { menu(for: task) }
                        .swipeActions(edge: .trailing) {
                            Button("Delete", systemImage: "trash", role: .destructive) { deleting = task }
                        }
                        .swipeActions(edge: .leading) {
                            Button("Complete", systemImage: "checkmark") { complete(task) }.tint(.green)
                        }
                }
            }
        }
        .navigationTitle("Backlog")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Ask Emo", systemImage: "sparkles") { isChatting = true }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                    .help("Describe a task and let Emo work out the details (⇧⌘N)")
                Button("Add Task", systemImage: "plus") { editor = .new }
                    .keyboardShortcut("n")
            }
        }
        .sheet(item: $editor) { target in
            switch target {
            case .new: TaskEditorSheet(task: nil)
            case .edit(let task): TaskEditorSheet(task: task)
            }
        }
        .sheet(item: $pinning) { PinTaskSheet(task: $0) }
        .sheet(isPresented: $isChatting) { TaskChatSheet() }
        .confirmationDialog(
            "Delete “\(deleting?.name ?? "")”?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            presenting: deleting
        ) { task in
            Button("Delete Task", role: .destructive) { delete(task) }
        } message: { _ in
            Text("Its scheduled blocks are removed too.")
        }
        .alert("Something went wrong", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func menu(for task: TaskItem) -> some View {
        Button("Edit…", systemImage: "pencil") { editor = .edit(task) }
        Button("Schedule at…", systemImage: "pin") { pinning = task }
        Button("Complete", systemImage: "checkmark.circle") { complete(task) }
        Divider()
        Button("Delete…", systemImage: "trash", role: .destructive) { deleting = task }
    }

    private var lifecycle: TaskLifecycle { TaskLifecycle(context: modelContext) }

    private func complete(_ task: TaskItem) {
        do { try lifecycle.complete(task) } catch { errorMessage = error.localizedDescription }
    }

    private func delete(_ task: TaskItem) {
        do { try lifecycle.delete(task) } catch { errorMessage = error.localizedDescription }
    }
}

private struct TaskRow: View {
    let task: TaskItem
    let today: LocalDay
    let onComplete: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Button(action: onComplete) {
                Image(systemName: "circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Mark as done")
            .accessibilityLabel("Complete \(task.name)")

            VStack(alignment: .leading, spacing: 2) {
                Text(task.name)
                    .font(.body)
                HStack(spacing: 8) {
                    Text(task.category.label)
                    if task.recurrence != .none {
                        Label(task.recurrence.label, systemImage: "repeat")
                    }
                    if let deadline = task.deadline {
                        Label(deadline.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                    }
                    if let from = task.availableFromDayKey.flatMap(LocalDay.init(key:)), from > today {
                        Label("From \(from.start().formatted(.dateTime.weekday(.abbreviated)))", systemImage: "clock")
                    }
                    if task.skippedDayKey == today.key {
                        Label("Skipped today", systemImage: "forward")
                    }
                    if task.needsReview {
                        Label("Review", systemImage: "exclamationmark.circle")
                            .foregroundStyle(.orange)
                            .help("Imported with a guessed size. Double-click to check the estimate and energy.")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text(task.estimatedHours.hoursLabel)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            EnergyBadge(cost: task.energyCost)
        }
        .padding(.vertical, 2)
    }
}

struct EnergyBadge: View {
    let cost: EnergyCost

    var body: some View {
        Text(cost.label)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(cost.tint.opacity(0.18), in: Capsule())
            .foregroundStyle(cost.tint)
    }
}

#Preview {
    let container = try! EmoStore.makeContainer(.inMemory)
    let backlog = Backlog(context: container.mainContext)
    try! backlog.add(TaskDraft(name: "Write quarterly report", estimatedHours: 2, energyCost: .high, category: .externalCommitment))
    try! backlog.add(TaskDraft(name: "Go for a run", estimatedHours: 0.75, energyCost: .medium, category: .selfCare, recurrence: .daily))
    return NavigationStack { BacklogView() }
        .modelContainer(container)
}
