import EmoKit
import SwiftData
import SwiftUI

/// The backlog on iPhone: tap to edit, swipe to complete or delete, + to add.
struct PhoneBacklogView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(Backlog.openTasksDescriptor) private var tasks: [TaskItem]
    @Query private var sessions: [TaskSession]
    @Query(sort: [SortDescriptor(\CategoryDefinition.sortIndex)]) private var categories: [CategoryDefinition]
    @Query private var blocks: [CalendarEvent]

    init() {
        _blocks = Query(TaskSchedule.futureBlocks(from: .now))
    }

    @State private var editing: TaskItem?
    @State private var searchText = ""
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
            } else if visibleTasks.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                List(Backlog.displayOrder(visibleTasks)) { task in
                    Button { editing = task } label: {
                        PhoneTaskRow(task: task, categories: categories, nextStart: nextStarts[task.id],
                                     doneThisWeek: doneThisWeek(task), doneToday: doneToday(task))
                    }
                        .foregroundStyle(.primary)
                        .swipeActions(edge: .leading) {
                            if !doneToday(task) {
                                Button(task.isDaily ? "Done Today" : "Complete", systemImage: "checkmark") { complete(task) }.tint(.green)
                            }
                            if task.looksVague {
                                Button("Clarify", systemImage: "sparkles") { clarifying = task }.tint(.indigo)
                            }
                        }
                        .contextMenu {
                            Button("Edit", systemImage: "pencil") { editing = task }
                            if task.listRole != nil, !task.isChecklist {
                                Button("Clarify with Emo", systemImage: "sparkles") { clarifying = task }
                            }
                            Button(task.isDaily ? "Done for Today" : "Complete", systemImage: "checkmark.circle") { complete(task) }
                                .disabled(doneToday(task))
                            Menu("Priority", systemImage: "arrow.up.arrow.down") {
                                ForEach(TaskPriority.allCases) { priority in
                                    Button(priority.label) { setPriority(priority, for: task) }
                                        .disabled(task.priority == priority)
                                }
                            }
                            Menu("Category", systemImage: "tag") {
                                ForEach(categories) { category in
                                    Button(category.name) { setCategory(category.taskCategory, for: task) }
                                        .disabled(task.categoryRaw == category.key)
                                }
                            }
                            // The checklist follows the routine list: it can't be stopped or deleted.
                            if task.isOngoing, !task.isChecklist {
                                Button("Stop Ongoing Task", systemImage: "stop.circle") { stop(task) }
                            }
                            if !task.isChecklist {
                                Divider()
                                Button("Delete", systemImage: "trash", role: .destructive) { deleting = task }
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            if !task.isChecklist {
                                Button("Delete", systemImage: "trash", role: .destructive) { deleting = task }
                            }
                        }
                }
            }
        }
        .navigationTitle("Backlog")
        .searchable(text: $searchText, prompt: "Search tasks")
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

    /// The tasks matching the search field (all of them when it's empty).
    private var visibleTasks: [TaskItem] { tasks.filter { $0.matches(searchText) } }

    /// When each task is next scheduled, from the calendar's future task blocks.
    private var nextStarts: [UUID: Date] { TaskSchedule.nextStarts(blocks) }

    private func setPriority(_ priority: TaskPriority, for task: TaskItem) {
        do { try TaskQuickEdit.apply({ $0.priority = priority }, to: task, context: modelContext) } catch { errorMessage = error.localizedDescription }
    }

    private func setCategory(_ category: TaskCategory, for task: TaskItem) {
        do { try TaskQuickEdit.apply({ $0.category = category }, to: task, context: modelContext) } catch { errorMessage = error.localizedDescription }
    }

    /// Completes a task; for an ongoing one, logs today's session instead.
    private func complete(_ task: TaskItem) {
        let lifecycle = TaskLifecycle(context: modelContext)
        do {
            if task.isOngoing { try lifecycle.logSession(task) } else { try lifecycle.complete(task) }
        } catch { errorMessage = error.localizedDescription }
    }

    /// Ends an ongoing task for good (its session history stays).
    private func stop(_ task: TaskItem) {
        do { try TaskLifecycle(context: modelContext).complete(task) } catch { errorMessage = error.localizedDescription }
    }

    private func doneThisWeek(_ task: TaskItem) -> Int {
        guard task.isOngoing else { return 0 }
        let keys = OngoingSchedule.weekKeys(containing: .today())
        return sessions.filter { $0.taskID == task.id && keys.contains($0.dayKey) }.count
    }

    private func doneToday(_ task: TaskItem) -> Bool {
        guard task.isDaily else { return false }
        let key = LocalDay.today().key
        return sessions.contains { $0.taskID == task.id && $0.dayKey == key }
    }

    private func delete(_ task: TaskItem) {
        do { try TaskLifecycle(context: modelContext).delete(task) } catch { errorMessage = error.localizedDescription }
    }
}

private struct PhoneTaskRow: View {
    let task: TaskItem
    let categories: [CategoryDefinition]
    var nextStart: Date?
    var doneThisWeek = 0
    var doneToday = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            if task.isRoutineItem {
                Image(systemName: doneToday ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(doneToday ? Color.green : .secondary)
                    .accessibilityLabel(doneToday ? "Done for today" : "Not done today")
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(task.name)
                if let partOf = task.partOf {
                    Text(partOf).font(.subheadline).foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    if task.isOngoing {
                        OngoingProgressLabel(task: task, doneThisWeek: doneThisWeek)
                    } else {
                        CategoryChip(key: task.categoryRaw, categories: categories)
                    }
                    PriorityTag(priority: task.priority)
                    if !task.isRoutineItem {
                        ScheduleLabel(start: nextStart)
                    }
                    if let deadline = task.deadline {
                        Label(deadline.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                    }
                    if task.needsReview {
                        Label(task.sizedFromMemory ? "Review · from memory" : "Review", systemImage: "exclamationmark.circle")
                            .foregroundStyle(.orange)
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
                if !task.isOngoing {
                    Text(task.estimatedHours.hoursLabel).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                }
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
