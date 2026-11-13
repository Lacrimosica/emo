import EmoKit
import SwiftData
import SwiftUI

/// The day at a glance. Hosts the check-in now; the timeline arrives with ticket 03.
struct TodayView: View {
    let day: LocalDay
    @Binding var isCheckingIn: Bool

    @Query private var checkIns: [CheckIn]

    init(day: LocalDay, isCheckingIn: Binding<Bool>) {
        self.day = day
        self._isCheckingIn = isCheckingIn
        self._checkIns = Query(CheckIns.descriptor(for: day))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(day.start().formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.largeTitle.weight(.semibold))

                CheckInCard(checkIn: checkIns.first) { isCheckingIn = true }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .navigationTitle("Today")
    }
}

private struct CheckInCard: View {
    let checkIn: CheckIn?
    let onEdit: () -> Void

    var body: some View {
        GroupBox {
            if let checkIn {
                HStack(spacing: 32) {
                    Meter(title: "Mood", value: checkIn.mood, systemImage: "face.smiling")
                    Meter(title: "Energy", value: checkIn.energy, systemImage: "bolt.fill")
                    Spacer()
                    Button("Edit", action: onEdit)
                }
                .padding(8)
            } else {
                HStack {
                    Label("You haven't checked in today.", systemImage: "sun.max")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Check In", action: onEdit)
                        .buttonStyle(.borderedProminent)
                }
                .padding(8)
            }
        } label: {
            Text("Check-in")
        }
    }
}

private struct Meter: View {
    let title: String
    let value: Int
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                ForEach(Array(CheckIns.scale), id: \.self) { n in
                    Capsule()
                        .fill(n <= value ? Color.accentColor : Color.secondary.opacity(0.2))
                        .frame(width: 18, height: 8)
                }
                Text("\(value)/5")
                    .font(.callout.monospacedDigit())
                    .padding(.leading, 4)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title) \(value) of 5")
        }
    }
}

#Preview {
    let container = try! EmoStore.makeContainer(.inMemory)
    try! CheckIns(context: container.mainContext).record(mood: 4, energy: 2, for: .today())
    return NavigationStack { TodayView(day: .today(), isCheckingIn: .constant(false)) }
        .modelContainer(container)
}
