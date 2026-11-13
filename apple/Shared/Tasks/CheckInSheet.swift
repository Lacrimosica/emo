import EmoKit
import SwiftData
import SwiftUI

/// Asks for mood and energy (1–5). Both are required; editing pre-fills the current values.
struct CheckInSheet: View {
    let day: LocalDay

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var mood: Int?
    @State private var energy: Int?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("How are you today?")
                    .font(.title2.weight(.semibold))
                Text(day.start().formatted(date: .complete, time: .omitted))
                    .foregroundStyle(.secondary)
            }

            ScaleRow(title: "Mood", lowLabel: "Low", highLabel: "Great", value: $mood)
            ScaleRow(title: "Energy", lowLabel: "Drained", highLabel: "Full", value: $energy)

            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.callout)
            }

            HStack {
                Spacer()
                Button("Later") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(mood == nil || energy == nil)
            }
        }
        .padding(24)
        .frame(width: 420)
        .onAppear(perform: loadExisting)
    }

    private func loadExisting() {
        guard let existing = try? CheckIns(context: modelContext).checkIn(for: day) else { return }
        mood = existing.mood
        energy = existing.energy
    }

    private func save() {
        guard let mood, let energy else { return }
        do {
            try CheckIns(context: modelContext).record(mood: mood, energy: energy, for: day)
            dismiss()
        } catch {
            errorMessage = "Couldn't save the check-in: \(error.localizedDescription)"
        }
    }
}

private struct ScaleRow: View {
    let title: String
    let lowLabel: String
    let highLabel: String
    @Binding var value: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            HStack(spacing: 8) {
                ForEach(Array(CheckIns.scale), id: \.self) { n in
                    Button {
                        value = n
                    } label: {
                        Text("\(n)")
                            .font(.title3.weight(.medium).monospacedDigit())
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(
                                value == n ? Color.accentColor : Color.secondary.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                            .foregroundStyle(value == n ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(title) \(n) of 5")
                    .accessibilityAddTraits(value == n ? .isSelected : [])
                }
            }
            HStack {
                Text(lowLabel)
                Spacer()
                Text(highLabel)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    CheckInSheet(day: .today())
        .modelContainer(try! EmoStore.makeContainer(.inMemory))
}
