import EmoKit
import SwiftData
import SwiftUI

struct BacklogView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(Backlog.openTasksDescriptor) private var tasks: [TaskItem]
    @Query private var sessions: [TaskSession]
    @Query(sort: [SortDescriptor(\CategoryDefinition.sortIndex)]) private var categories: [CategoryDefinition]
    @Query private var blocks: [CalendarEvent]

    init() {
        _blocks = Query(TaskSchedule.futureBlocks(from: .now))
    }

    @State private var editor: EditorTarget?
    @State private var searchText = ""
    @State private var isChatting = false
    @State private var isAddingContext = false
    /// The task "Clarify with Emo" is open for.
    @State private var clarifying: TaskItem?
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
            } else if visibleTasks.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                List {
                    ForEach(groups, id: \.title) { group in
                        Section {
                            ForEach(group.tasks) { row(for: $0) }
                        } header: {
                            if let title = group.title { Label(title, systemImage: group.systemImage) }
                        } footer: {
                            if let note = group.note { Text(note) }
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
                    Button("New Task…", systemImage: "plus.bubble") { isChatting = true }
                        .keyboardShortcut("n", modifiers: [.command, .shift])
                    Button("Add Context to Reminders…", systemImage: "text.bubble") { isAddingContext = true }
                } label: {
                    Label("Ask Emo", systemImage: "sparkles")
                } primaryAction: {
                    isChatting = true
                }
                .help("Describe a task and let Emo work out the details (⇧⌘N); hold for adding context to reminders")
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
        .sheet(isPresented: $isAddingContext) { ContextChatSheet() }
        .sheet(item: $clarifying) { ContextChatSheet(scope: $0) }
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

    private func row(for task: TaskItem) -> some View {
        TaskRow(task: task, today: .today(), categories: categories, nextStart: nextStarts[task.id],
                doneThisWeek: doneThisWeek(task), doneToday: doneToday(task)) { complete(task) }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { editor = .edit(task) }
            .contextMenu { menu(for: task) }
            .swipeActions(edge: .trailing) {
                Button("Delete", systemImage: "trash", role: .destructive) { deleting = task }
            }
            .swipeActions(edge: .leading) {
                Button(task.isDaily ? "Done Today" : "Complete", systemImage: "checkmark") { complete(task) }.tint(.green)
            }
    }

    private struct RoleGroup {
        var title: String?
        var systemImage = ""
        var note: String?
        var tasks: [TaskItem]
    }

    /// Schedulable work first (untitled), then each kept-but-unscheduled role in list order.
    private var groups: [RoleGroup] {
        let byRole = Dictionary(grouping: visibleTasks.filter { !$0.isSchedulable }) { $0.listRole! }
        let parked = ListRole.allCases.filter { !$0.isSchedulable }.compactMap { role -> RoleGroup? in
            guard let tasks = byRole[role] else { return nil }
            return RoleGroup(title: role.label, systemImage: role.systemImage, note: role == .inbox
                         ? "Clarify these in Reminders: move each to an NA list to have it scheduled." : nil,
                         tasks: tasks)
        }
        let active = Backlog.displayOrder(visibleTasks.filter { $0.isSchedulable && !$0.isRoutineItem })
        let routine = visibleTasks.filter(\.isRoutineItem)
        let checklist = routine.isEmpty ? [] : [RoleGroup(
            title: "Checklist items", systemImage: "checklist",
            note: "Planned together as one daily checklist block. Ticking an item marks it done for today.", tasks: routine)]
        let untitled = parked.isEmpty && checklist.isEmpty
        return (active.isEmpty ? [] : [RoleGroup(title: untitled ? nil : "To do", systemImage: "calendar", tasks: active)]) + checklist + parked
    }

    @ViewBuilder
    private func menu(for task: TaskItem) -> some View {
        Button("Edit…", systemImage: "pencil") { editor = .edit(task) }
        Button("Schedule at…", systemImage: "pin") { pinning = task }
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
        // The checklist is Emo's own: it follows the routine list, so it can't be stopped, clarified or deleted.
        if task.isOngoing, !task.isChecklist {
            Button("Stop Ongoing Task", systemImage: "stop.circle") { stop(task) }
        }
        if task.listRole != nil, !task.isChecklist {
            Button("Clarify with Emo…", systemImage: "sparkles") { clarifying = task }
        }
        if !task.isChecklist {
            Divider()
            Button("Delete…", systemImage: "trash", role: .destructive) { deleting = task }
        }
    }

    private var lifecycle: TaskLifecycle { TaskLifecycle(context: modelContext) }

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
        do {
            if task.isOngoing { try lifecycle.logSession(task) } else { try lifecycle.complete(task) }
        } catch { errorMessage = error.localizedDescription }
    }

    /// Ends an ongoing task for good (its session history stays).
    private func stop(_ task: TaskItem) {
        do { try lifecycle.complete(task) } catch { errorMessage = error.localizedDescription }
    }

    private func doneThisWeek(_ task: TaskItem) -> Int {
        guard task.isOngoing else { return 0 }
        let keys = OngoingSchedule.weekKeys(containing: .today())
        return sessions.filter { $0.taskID == task.id && keys.contains($0.dayKey) }.count
    }

    /// A routine item ticked today, or an ongoing task whose session today is logged.
    private func doneToday(_ task: TaskItem) -> Bool {
        guard task.isDaily else { return false }
        let key = LocalDay.today().key
        return sessions.contains { $0.taskID == task.id && $0.dayKey == key }
    }

    private func delete(_ task: TaskItem) {
        do { try lifecycle.delete(task) } catch { errorMessage = error.localizedDescription }
    }
}

private struct TaskRow: View {
    let task: TaskItem
    let today: LocalDay
    let categories: [CategoryDefinition]
    /// When the task is next scheduled; nil if it isn't.
    var nextStart: Date?
    var doneThisWeek = 0
    var doneToday = false
    let onComplete: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Button(action: onComplete) {
                Image(systemName: doneToday ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(doneToday ? Color.green : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(doneToday)
            .help(doneToday ? "Done for today" : task.isDaily ? "Done for today" : "Mark as done")
            .accessibilityLabel(doneToday ? "\(task.name), done for today"
                                : task.isRoutineItem ? "Tick \(task.name) for today"
                                : task.isOngoing ? "Log a session of \(task.name)" : "Complete \(task.name)")

            VStack(alignment: .leading, spacing: 2) {
                Text(task.name)
                    .font(.body)
                if let partOf = task.partOf {
                    Text(partOf)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .help("Part of “\(partOf)” (from the reminder's notes)")
                }
                HStack(spacing: 8) {
                    if let area = task.listArea {
                        Label(area, systemImage: task.listRole?.systemImage ?? "list.bullet")
                    }
                    CategoryChip(key: task.categoryRaw, categories: categories)
                    PriorityTag(priority: task.priority)
                    if !task.isRoutineItem {
                        ScheduleLabel(start: nextStart)
                    }
                    if task.isOngoing {
                        OngoingProgressLabel(task: task, doneThisWeek: doneThisWeek)
                    }
                    if task.recurrence != .none {
                        Label(task.recurrence.label, systemImage: "repeat")
                    }
                    if let deadline = task.deadline {
                        Label(deadline.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                    }
                    if let from = task.availableFromDayKey.flatMap(LocalDay.init(key:)), from > today {
                        Label("From \(from.start().formatted(.dateTime.weekday(.abbreviated)))", systemImage: "clock")
                    }
                    if task.isSkipped(on: today) {
                        Label("Skipped today", systemImage: "forward")
                    }
                    if task.needsReview {
                        Label(task.sizedFromMemory ? "Review · sized from memory" : "Review", systemImage: "exclamationmark.circle")
                            .foregroundStyle(.orange)
                            .help(task.sizedFromMemory
                                  ? "Sized like similar tasks you sized before. Double-click to check it."
                                  : "Imported with a guessed size. Double-click to check the estimate and energy.")
                    }
                    if task.looksVague {
                        Label("Needs context", systemImage: "sparkles")
                            .foregroundStyle(.indigo)
                            .help("Emo can't tell much from this title. Right-click › Clarify with Emo to add a note.")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if !task.isOngoing {
                Text(task.estimatedHours.hoursLabel)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            EnergyBadge(cost: task.energyCost)
        }
        .padding(.vertical, 2)
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
