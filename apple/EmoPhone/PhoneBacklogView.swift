import EmoKit
import SwiftData
import SwiftUI

/// The backlog on iPhone: tap to edit, swipe to complete or delete, + to add.
struct PhoneBacklogView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(Backlog.openTasksDescriptor) private var tasks: [TaskItem]

    @State private var editing: TaskItem?
    @State private var isAdding = false
    @State private var isChatting = false
    @State private var isAddingContext = false
    @State private var clarifying: TaskItem?
    @State private var deleting: TaskItem?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if tasks.isEmpty {
                ContentUnavailableView {
                    Label("No Tasks", systemImage: "tray")
                } description: {
                    Text("Add a task to start filling your backlog.")
                } actions: {
                    Button("Ask Emo", systemImage: "sparkles") { isChatting = true }
                        .buttonStyle(.borderedProminent)
                    Button("Add Task") { isAdding = true }
                }
            } else {
                List(tasks) { task in
                    Button { editing = task } label: { PhoneTaskRow(task: task) }
                        .foregroundStyle(.primary)
                        .swipeActions(edge: .leading) {
                            Button("Complete", systemImage: "checkmark") { complete(task) }.tint(.green)
                            if task.looksVague {
                                Button("Clarify", systemImage: "sparkles") { clarifying = task }.tint(.indigo)
                            }
                        }
                        .contextMenu {
                            Button("Edit", systemImage: "pencil") { editing = task }
                            if task.listRole != nil {
                                Button("Clarify with Emo", systemImage: "sparkles") { clarifying = task }
                            }
                            Button("Complete", systemImage: "checkmark.circle") { complete(task) }
                            Divider()
                            Button("Delete", systemImage: "trash", role: .destructive) { deleting = task }
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Delete", systemImage: "trash", role: .destructive) { deleting = task }
                        }
                }
            }
        }
        .navigationTitle("Backlog")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Button("New Task", systemImage: "plus.bubble") { isChatting = true }
                    Button("Add Context to Reminders", systemImage: "text.bubble") { isAddingContext = true }
                } label: {
                    Label("Ask Emo", systemImage: "sparkles")
                } primaryAction: {
                    isChatting = true
                }
                Button("Add Task", systemImage: "plus") { isAdding = true }
            }
        }
        .sheet(isPresented: $isAdding) {
            NavigationStack { TaskEditorSheet(task: nil) }
        }
        .sheet(isPresented: $isChatting) {
            NavigationStack { TaskChatSheet() }
        }
        .sheet(isPresented: $isAddingContext) {
            NavigationStack { ContextChatSheet() }
        }
        .sheet(item: $clarifying) { task in
            NavigationStack { ContextChatSheet(scope: task) }
        }
        .sheet(item: $editing) { task in
            NavigationStack { TaskEditorSheet(task: task) }
        }
        .confirmationDialog("Delete “\(deleting?.name ?? "")”?",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible, presenting: deleting) { task in
            Button("Delete Task", role: .destructive) { delete(task) }
        } message: { _ in
            Text("Its scheduled blocks are removed too.")
        }
        .alert("Something went wrong", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func complete(_ task: TaskItem) {
        do { try TaskLifecycle(context: modelContext).complete(task) } catch { errorMessage = error.localizedDescription }
    }

    private func delete(_ task: TaskItem) {
        do { try TaskLifecycle(context: modelContext).delete(task) } catch { errorMessage = error.localizedDescription }
    }
}

private struct PhoneTaskRow: View {
    let task: TaskItem

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(task.name)
                if let partOf = task.partOf {
                    Text(partOf).font(.subheadline).foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    Text(task.category.label)
                    if let deadline = task.deadline {
                        Label(deadline.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                    }
                    if task.needsReview {
                        Label("Review", systemImage: "exclamationmark.circle").foregroundStyle(.orange)
                    }
                    if task.looksVague {
                        Label("Needs context", systemImage: "sparkles").foregroundStyle(.indigo)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(task.estimatedHours.hoursLabel).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                EnergyBadge(cost: task.energyCost)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the task")
    }
}

#Preview {
    let container = try! EmoStore.makeContainer(.inMemory)
    try! Backlog(context: container.mainContext).add(TaskDraft(name: "Write quarterly report", estimatedHours: 2, energyCost: .high))
    return NavigationStack { PhoneBacklogView() }.modelContainer(container)
}
