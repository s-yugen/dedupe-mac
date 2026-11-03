import AppKit
import SwiftUI

/// Light, dark, or follow the macOS setting. Saved in UserDefaults.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let key = "Appearance"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Use System Setting"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var systemImage: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    /// Setting `NSApp.appearance` also themes the Open dialog, alerts and
    /// menus, which SwiftUI's `preferredColorScheme` does not reach.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    static var saved: AppearanceMode {
        UserDefaults.standard.string(forKey: key).flatMap(AppearanceMode.init(rawValue:)) ?? .system
    }

    @MainActor
    static func apply(_ mode: AppearanceMode) {
        NSApp?.appearance = mode.nsAppearance
    }
}

/// View > Appearance submenu.
struct AppearanceCommands: Commands {
    @AppStorage(AppearanceMode.key) private var appearance = AppearanceMode.system

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Divider()
            Picker("Appearance", selection: $appearance) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
        }
    }
}

/// Toolbar control. A click switches between light and dark. The arrow
/// opens a menu that also offers the system setting.
struct AppearanceToolbarButton: View {
    @AppStorage(AppearanceMode.key) private var appearance = AppearanceMode.system
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Menu {
            Picker("Appearance", selection: $appearance) {
                ForEach(AppearanceMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.systemImage).tag(mode)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Label("Appearance", systemImage: colorScheme == .dark ? "moon.fill" : "sun.max.fill")
        } primaryAction: {
            appearance = colorScheme == .dark ? .light : .dark
        }
        .help(colorScheme == .dark ? "Switch to light mode" : "Switch to dark mode")
    }
}
