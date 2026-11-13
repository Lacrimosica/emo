import SwiftUI

/// Settings on iPhone.
struct PhoneSettingsView: View {
    var body: some View {
        List {
            NavigationLink {
                PlanningSettingsView()
                    .navigationTitle("Planning")
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                Label("Planning", systemImage: "calendar.day.timeline.left")
            }
            NavigationLink {
                IntegrationsSettingsView()
                    .navigationTitle("Integrations")
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                Label("Calendar & Reminders", systemImage: "link")
            }
            NavigationLink {
                AISettingsView()
                    .navigationTitle("AI")
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                Label("AI", systemImage: "sparkles")
            }
        }
        .navigationTitle("Settings")
    }
}
