import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The app icons the user can choose from (Settings › App Icon). Lilac is the main one, the one
/// in the bundle; the rest are drawn by `apple/Artwork/render.swift` in other palettes.
enum AppIconChoice: String, CaseIterable, Identifiable {
    case lilac, night, swiss, teal, mustard

    var id: String { rawValue }
    static let storageKey = "appIconChoice"

    var label: String {
        switch self {
        case .lilac: "Lilac"
        case .night: "Night"
        case .swiss: "Swiss"
        case .teal: "Teal"
        case .mustard: "Mustard"
        }
    }

    /// Image set used for the picker (and, on the Mac, for the Dock).
    var previewName: String { "AppIconPreview-\(rawValue)" }

    /// The iOS alternate icon set (`ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`); nil is the main icon.
    var alternateIconName: String? { self == .lilac ? nil : "AppIcon-\(rawValue)" }
}

@MainActor
enum AppIconSwitcher {
    #if os(macOS)
    /// Sets the Dock icon. macOS forgets it when Emo quits, so `RootView` applies it again at launch.
    /// Finder and Launchpad keep the bundle's icon: changing that would mean writing into the signed app.
    static func apply(_ choice: AppIconChoice) {
        NSApplication.shared.applicationIconImage = choice == .lilac ? nil : NSImage(named: choice.previewName)
    }
    #else
    /// The icon iOS is showing now.
    static var current: AppIconChoice {
        AppIconChoice.allCases.first { $0.alternateIconName == UIApplication.shared.alternateIconName } ?? .lilac
    }

    /// Changes the home-screen icon (iOS shows a short confirmation).
    static func apply(_ choice: AppIconChoice) async throws {
        guard UIApplication.shared.supportsAlternateIcons else { throw SwitchError.unsupported }
        try await UIApplication.shared.setAlternateIconName(choice.alternateIconName)
    }

    enum SwitchError: LocalizedError {
        case unsupported
        var errorDescription: String? { "This device doesn't allow changing the app icon." }
    }
    #endif
}

/// Settings › App Icon: pick one of Emo's icons.
struct AppIconSettingsView: View {
    @AppStorage(AppIconChoice.storageKey) private var selected: AppIconChoice = .lilac
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12)], spacing: 12) {
                    ForEach(AppIconChoice.allCases) { choice in
                        Button { select(choice) } label: { tile(choice) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(choice.label) icon")
                            .accessibilityAddTraits(choice == selected ? .isSelected : [])
                    }
                }
                .padding(.vertical, 6)
            } footer: {
                #if os(macOS)
                Text("Changes Emo's icon in the Dock. Finder and Launchpad keep the Lilac icon.")
                #else
                Text("Changes Emo's icon on the Home Screen.")
                #endif
            }

            if let errorMessage {
                Text(errorMessage).font(.callout).foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        #if os(iOS)
        .onAppear { selected = AppIconSwitcher.current }
        #endif
    }

    private func tile(_ choice: AppIconChoice) -> some View {
        VStack(spacing: 6) {
            Image(choice.previewName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 76, height: 76)
                #if os(iOS)
                .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                #endif
            Label(choice.label, systemImage: choice == selected ? "checkmark.circle.fill" : "circle")
                .font(.caption)
                .foregroundStyle(choice == selected ? Color.accentColor : .secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(Color.accentColor.opacity(choice == selected ? 0.12 : 0), in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
    }

    private func select(_ choice: AppIconChoice) {
        errorMessage = nil
        #if os(macOS)
        selected = choice
        AppIconSwitcher.apply(choice)
        #else
        Task {
            do {
                try await AppIconSwitcher.apply(choice)
                selected = choice
            } catch {
                errorMessage = "Couldn't change the icon: \(error.localizedDescription)"
            }
        }
        #endif
    }
}
