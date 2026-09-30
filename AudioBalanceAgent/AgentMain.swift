import AppKit

/// Entry point for the background agent launched by launchd from
/// `Contents/Library/LaunchAgents/dev.joshuapark.AudioBalance.Agent.plist`.
@main
enum AgentMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AgentDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        // NSApplication holds its delegate weakly; keep it alive for the life of the run loop.
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}

final class AgentDelegate: NSObject, NSApplicationDelegate {
    private let settings = SharedSettings()
    private lazy var notifier = Notifier()
    private lazy var monitor = BalanceMonitor(settings: settings, notifier: notifier)
    private var settingsObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        settingsObserver = DistributedNotificationCenter.default().addObserver(
            forName: SharedSettings.Notification.settingsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.settingsDidChange() }
        }
        if settings.notifyOnFix { notifier.requestAuthorization() }
        monitor.start()
    }

    private func settingsDidChange() {
        settings.synchronize()
        if settings.notifyOnFix { notifier.requestAuthorization() }
        monitor.lockPointDidChange()
    }
}
