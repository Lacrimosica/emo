import EmoKit
import SwiftData
import SwiftUI

/// Settings › Categories: the user's task categories, with an optional weekly time target each.
struct CategoriesSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\CategoryDefinition.sortIndex)]) private var categories: [CategoryDefinition]

    @State private var editing: CategoryDefinition?
    @State private var isAdding = false
    @State private var deleting: CategoryDefinition?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                ForEach(categories) { category in
                    Button { editing = category } label: {
                        HStack {
                            CategoryChip(key: category.key, categories: categories)
                            Spacer()
                            Text(targetLabel(category)).font(.callout).foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        if !category.isBuiltIn {
                            Button("Delete", systemImage: "trash", role: .destructive) { deleting = category }
                        }
                    }
                    .contextMenu {
                        Button("Edit…", systemImage: "pencil") { editing = category }
                        if !category.isBuiltIn {
                            Button("Delete…", systemImage: "trash", role: .destructive) { deleting = category }
                        }
                    }
                }
            } footer: {
                Text("Every task has one category. A weekly target asks the planner to fit that much time in the category each week, ahead of tasks that aren't behind.")
            }

            Section {
                Button("Add Category", systemImage: "plus") { isAdding = true }
            }
        }
        .formStyle(.grouped)
        .sheet(item: $editing) { CategoryEditorSheet(category: $0) }
        .sheet(isPresented: $isAdding) { CategoryEditorSheet(category: nil) }
        .confirmationDialog(
            "Delete “\(deleting?.name ?? "")”?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            presenting: deleting
        ) { category in
            Button("Delete Category", role: .destructive) { delete(category) }
        } message: { _ in
            Text("Its tasks move to Personal.")
        }
        .alert("Something went wrong", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func targetLabel(_ category: CategoryDefinition) -> String {
        category.weeklyHours > 0 ? "\(category.weeklyHours.hoursLabel) a week" : "No target"
    }

    private func delete(_ category: CategoryDefinition) {
        do { try CategoryCatalog(context: modelContext).delete(category) } catch { errorMessage = error.localizedDescription }
    }
}

/// Adds or edits one category: name, colour and weekly target.
private struct CategoryEditorSheet: View {
    /// nil to add a new one.
    let category: CategoryDefinition?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var colorHex = CategoryEditorSheet.palette[0]
    @State private var symbol = "tag"
    @State private var weeklyHours = 0.0
    @State private var errorMessage: String?

    /// Colours offered for a category, as "#RRGGBB".
    static let palette = ["#E0523D", "#E8912D", "#D9B42B", "#3FA76B", "#2AA3A3", "#4A7BD0", "#9B6BCB", "#D0568C", "#7A7A7A"]

    /// Icons offered for a category (SF Symbols).
    static let symbols = ["tag", "person.2", "heart", "house", "figure.walk", "briefcase", "book", "graduationcap",
                          "cart", "doc.text", "wrench.and.screwdriver", "paintbrush", "music.note", "fork.knife",
                          "leaf", "dumbbell", "phone", "laptopcomputer", "car", "star"]

    var body: some View {
        Form {
            TextField("Name", text: $name, prompt: Text("e.g. Admin"))

            Section("Colour") {
                HStack(spacing: 10) {
                    ForEach(Self.palette, id: \.self) { hex in
                        Button { colorHex = hex } label: {
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 26, height: 26)
                                .overlay {
                                    if hex == colorHex { Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white) }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(hex == colorHex ? "Selected colour" : "Colour")
                    }
                }
            }

            Section("Icon") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 10), spacing: 6) {
                    ForEach(Self.symbols, id: \.self) { name in
                        Button { symbol = name } label: {
                            Image(systemName: name)
                                .frame(width: 28, height: 28)
                                .foregroundStyle(name == symbol ? Color.white : Color(hex: colorHex))
                                .background(name == symbol ? Color(hex: colorHex) : Color(hex: colorHex).opacity(0.12),
                                            in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(name == symbol ? "\(name), selected" : name)
                    }
                }
            }

            Section {
                Stepper(value: $weeklyHours, in: CategoryCatalog.weeklyHoursRange, step: 0.5) {
                    LabeledContent("Weekly target", value: weeklyHours > 0 ? "\(weeklyHours.hoursLabel) a week" : "None")
                }
            } footer: {
                Text("Leave at None for a category with no target.")
            }

            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.callout)
            }
        }
        .formStyle(.grouped)
        #if os(macOS)
        .frame(minWidth: 420)
        #endif
        .navigationTitle(category == nil ? "New Category" : "Edit Category")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(category == nil ? "Add" : "Save", action: save)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onAppear {
            guard let category else { return }
            name = category.name
            colorHex = category.colorHex
            symbol = category.symbol
            weeklyHours = category.weeklyHours
        }
    }

    private func save() {
        let catalog = CategoryCatalog(context: modelContext)
        do {
            if let category {
                try catalog.update(category, name: name, colorHex: colorHex, weeklyHours: weeklyHours, symbol: symbol)
            } else {
                try catalog.add(name: name, colorHex: colorHex, symbol: symbol, weeklyHours: weeklyHours)
            }
            dismiss()
        } catch {
            errorMessage = "Couldn't save the category: \(error.localizedDescription)"
        }
    }
}
