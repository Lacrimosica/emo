import EmoKit
import SwiftData
import SwiftUI

/// Planning settings (day window, shortest block, energy budget). Changes save as soon as they're valid.
struct PlanningSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var settings = PlannerSettings.default
    @State private var loaded = false
    @State private var errorMessage: String?

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
        }
        .formStyle(.grouped)
        .onAppear {
            settings = PlannerSettingsStore(context: modelContext).load()
            loaded = true
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
