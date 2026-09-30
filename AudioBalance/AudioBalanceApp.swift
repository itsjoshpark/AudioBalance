import SwiftUI

@main
struct AudioBalanceApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("Audio Balance", id: "main") {
            SettingsView(model: model)
        }
        .windowResizability(.contentSize)
        .windowToolbarStyle(.unifiedCompact)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The window is only a control panel; the agent keeps working after the app quits.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
