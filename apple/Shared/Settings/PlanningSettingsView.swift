import EmoKit
import SwiftData
import SwiftUI

/// Planning settings (day window, shortest block, energy budget). Changes save as soon as they're valid.
struct PlanningSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var settings = PlannerSettings.default
    @State private var loaded = false
    @State private var errorMessage: String?
    @State private var learnedTimes: [TimeOfDayMemory.Learned] = []
    @State private var sizedCount = 0
    @State private var confirmingForget: ForgetTarget?

    private enum ForgetTarget: Identifiable {
        case times, sizing
        var id: Self { self }
    }

    var body: some View {
        Form {
            Section {
                DatePicker("Start planning at", selection: minutesBinding(\.dayStartMinutes), displayedComponents: .hourAndMinute)
                DatePicker("Stop planning at", selection: minutesBinding(\.dayEndMinutes), displayedComponents: .hourAndMinute)
            } header: {
                Text("Day")
            } footer: {
                Text("Emo only places tasks inside this window. Your own events can be anywhere.")
                    .foregroundStyle(.secondary)
            }

            Section("Blocks") {
                Stepper(value: $settings.minimumChunkMinutes, in: PlannerSettingsStore.minimumChunkRange, step: 5) {
                    LabeledContent("Shortest block", value: "\(settings.minimumChunkMinutes) min")
                }
            }

            Section {
                ForEach(1...5, id: \.self) { level in
                    Stepper(value: budgetBinding(level), in: PlannerSettingsStore.budgetRange, step: 0.5) {
                        LabeledContent("Energy \(level)", value: (settings.energyBudgetHours[level] ?? 0).hoursLabel)
                    }
                }
                Picker("Without a check-in, assume", selection: $settings.defaultEnergy) {
                    ForEach(1...5, id: \.self) { Text("Energy \($0)").tag($0) }
                }
            } header: {
                Text("Daily task budget")
            } footer: {
                Text("How much task work Emo plans for a day, based on that day's energy check-in.")
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }

            Button("Restore Defaults") { settings = .default }

            Section {
                if learnedTimes.isEmpty {
                    Text("No time-of-day patterns yet. Emo learns them as you complete tasks and move blocks.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(learnedTimes) { learned in
                        LabeledContent {
                            Text(windowText(learned.window)).monospacedDigit()
                        } label: {
                            Label(learned.name.capitalized, systemImage: learned.isArea ? "folder" : "tag")
                        }
                        .accessibilityLabel("\(learned.name): usually \(windowText(learned.window))")
                    }
                }
                LabeledContent("Task sizes remembered", value: "\(sizedCount)")
                Button("Forget Times…", role: .destructive) { confirmingForget = .times }
                    .disabled(learnedTimes.isEmpty)
                Button("Forget Task Sizes…", role: .destructive) { confirmingForget = .sizing }
                    .disabled(sizedCount == 0)
            } header: {
                Text("What Emo has learned")
            } footer: {
                Text("Emo plans these kinds of tasks at these times when they're free, and sizes new reminders like similar tasks you've sized. Nothing leaves this device.")
                    .foregroundStyle(.secondary)
            }
        }
        .confirmationDialog(confirmingForget == .times ? "Forget time-of-day patterns?" : "Forget remembered task sizes?",
                            isPresented: Binding(get: { confirmingForget != nil }, set: { if !$0 { confirmingForget = nil } }),
                            titleVisibility: .visible) {
            Button("Forget", role: .destructive) { forget() }
        } message: {
            Text("Emo starts learning again from scratch.")
        }
        .formStyle(.grouped)
        .onAppear {
            settings = PlannerSettingsStore(context: modelContext).load()
            loaded = true
            loadLearned()
        }
        .onChange(of: settings) { _, new in
            guard loaded else { return }
            do {
                try PlannerSettingsStore(context: modelContext).save(new)
                errorMessage = nil
            } catch let error as PlannerSettingsStore.ValidationError {
                errorMessage = error.message
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func loadLearned() {
        learnedTimes = (try? TimeOfDayMemory(context: modelContext).learned()) ?? []
        sizedCount = (try? SchedulingMemory(context: modelContext).count()) ?? 0
    }

    private func forget() {
        switch confirmingForget {
        case .times: try? TimeOfDayMemory(context: modelContext).reset()
        case .sizing: try? SchedulingMemory(context: modelContext).reset()
        case nil: break
        }
        confirmingForget = nil
        loadLearned()
    }

    private func windowText(_ window: PreferredWindow) -> String {
        let midnight = Calendar.current.startOfDay(for: .now)
        let start = midnight.addingTimeInterval(TimeInterval(window.startMinutes * 60))
        let end = midnight.addingTimeInterval(TimeInterval(window.endMinutes * 60))
        return "\(start.formatted(date: .omitted, time: .shortened)) – \(end.formatted(date: .omitted, time: .shortened))"
    }

    /// Bridges "minutes after midnight" to a `Date` for the time pickers.
    private func minutesBinding(_ keyPath: WritableKeyPath<PlannerSettings, Int>) -> Binding<Date> {
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: .now)
        return Binding(
            get: { calendar.date(byAdding: .minute, value: settings[keyPath: keyPath], to: midnight)! },
            set: { date in
                let c = calendar.dateComponents([.hour, .minute], from: date)
                settings[keyPath: keyPath] = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }
        )
    }

    private func budgetBinding(_ level: Int) -> Binding<Double> {
        Binding(
            get: { settings.energyBudgetHours[level] ?? 0 },
            set: { settings.energyBudgetHours[level] = $0 }
        )
    }
}

extension PlannerSettingsStore.ValidationError {
    var message: String {
        switch self {
        case .dayEndNotAfterStart: "The planning window must end after it starts."
        case .dayBoundsOutOfRange: "Planning times must be within the day."
        case .minimumChunkOutOfRange: "The shortest block must be between 5 minutes and 4 hours."
        case .budgetOutOfRange: "Each daily budget must be between 0 and 24 hours."
        case .defaultEnergyOutOfRange: "Default energy must be between 1 and 5."
        }
    }
}
