import EmoKit
import SwiftData
import SwiftUI

struct BacklogView: View {
    @Query(Backlog.openTasksDescriptor) private var tasks: [TaskItem]
    @State private var isAddingTask = false

    var body: some View {
        Group {
            if tasks.isEmpty {
                ContentUnavailableView {
                    Label("No Tasks", systemImage: "tray")
                } description: {
                    Text("Add a task to start filling your backlog.")
                } actions: {
                    Button("Add Task") { isAddingTask = true }
                }
            } else {
                List(tasks) { task in
                    TaskRow(task: task)
                }
            }
        }
        .navigationTitle("Backlog")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Task", systemImage: "plus") { isAddingTask = true }
                    .keyboardShortcut("n")
            }
        }
        .sheet(isPresented: $isAddingTask) {
            AddTaskSheet()
        }
    }
}

private struct TaskRow: View {
    let task: TaskItem

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(task.name)
                    .font(.body)
                HStack(spacing: 8) {
                    Text(task.category.label)
                    if let deadline = task.deadline {
                        Label(deadline.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
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
    try! backlog.add(TaskDraft(name: "Go for a run", estimatedHours: 0.75, energyCost: .medium, category: .selfCare))
    return NavigationStack { BacklogView() }
        .modelContainer(container)
}
