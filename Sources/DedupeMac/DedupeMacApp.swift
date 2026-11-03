import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when the binary runs straight from Xcode or `swift run`
        // without an app bundle. Otherwise the window opens behind others
        // and the app has no Dock icon or menu bar.
        NSApp.setActivationPolicy(.regular)
        AppearanceMode.apply(.saved)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct DedupeMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()
    @AppStorage(AppearanceMode.key) private var appearance = AppearanceMode.system

    var body: some Scene {
        Window("Dedupe", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 960, minHeight: 600)
                .onChange(of: appearance, initial: true) { _, mode in
                    AppearanceMode.apply(mode)
                }
        }
        .windowResizability(.contentMinSize)
        .commands {
            TextSizeCommands()
            AppearanceCommands()
        }
    }
}

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationSplitView {
            SetupView()
                .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 440)
        } detail: {
            ResultsView()
                .overlay { ToastOverlay() }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                AppearanceToolbarButton()
            }
        }
        .alert(
            model.alert?.title ?? "",
            isPresented: Binding(
                get: { model.alert != nil },
                set: { if !$0 { model.alert = nil } }
            ),
            presenting: model.alert
        ) { _ in
            Button("OK") { model.alert = nil }
        } message: { alert in
            Text(alert.message)
        }
    }
}

extension Int64 {
    var formattedBytes: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}
