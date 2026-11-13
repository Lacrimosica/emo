import EmoKit
import SwiftData
import SwiftUI

/// Emo › Settings… (⌘,). Changes apply as soon as they're valid, like other Mac settings windows.
struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("Planning", systemImage: "calendar.day.timeline.left") {
                PlanningSettingsView()
            }
            Tab("AI", systemImage: "sparkles") {
                AISettingsView()
            }
            Tab("Integrations", systemImage: "link") {
                IntegrationsSettingsView()
            }
        }
        .frame(width: 460)
    }
}
