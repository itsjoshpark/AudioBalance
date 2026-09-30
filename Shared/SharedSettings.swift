import Foundation

/// Settings shared between the settings app and the background agent.
///
/// Both processes read and write the settings app's preferences domain; neither is sandboxed.
/// After writing, the app posts ``Notification/settingsChanged`` so the agent reloads immediately,
/// and the agent posts ``Notification/balanceFixed`` after each correction.
nonisolated struct SharedSettings: @unchecked Sendable {
    static let domain = "dev.joshuapark.AudioBalance"
    static let agentBundleIdentifier = "dev.joshuapark.AudioBalance.Agent"
    static let agentPlistName = "dev.joshuapark.AudioBalance.Agent.plist"

    enum Key {
        static let lockPoint = "lockPoint"
        static let notifyOnFix = "notifyOnFix"
        static let lastFixDate = "lastFixDate"
        static let lastFixDevice = "lastFixDevice"
    }

    enum Notification {
        static let settingsChanged = Foundation.Notification.Name("dev.joshuapark.AudioBalance.settingsChanged")
        static let balanceFixed = Foundation.Notification.Name("dev.joshuapark.AudioBalance.balanceFixed")
    }

    let defaults: UserDefaults

    init(defaults: UserDefaults? = nil) {
        if let defaults {
            self.defaults = defaults
        } else if Bundle.main.bundleIdentifier == Self.domain {
            // A suite named after the running app's own bundle identifier is not allowed.
            self.defaults = .standard
        } else {
            self.defaults = UserDefaults(suiteName: Self.domain) ?? .standard
        }
        self.defaults.register(defaults: [
            Key.lockPoint: BalancePolicy.center,
            Key.notifyOnFix: true,
        ])
    }

    var lockPoint: Float {
        get { BalancePolicy.clamped(defaults.float(forKey: Key.lockPoint)) }
        nonmutating set { defaults.set(BalancePolicy.clamped(newValue), forKey: Key.lockPoint) }
    }

    var notifyOnFix: Bool {
        get { defaults.bool(forKey: Key.notifyOnFix) }
        nonmutating set { defaults.set(newValue, forKey: Key.notifyOnFix) }
    }

    var lastFixDate: Date? { defaults.object(forKey: Key.lastFixDate) as? Date }
    var lastFixDevice: String? { defaults.string(forKey: Key.lastFixDevice) }

    func recordFix(on deviceName: String?, at date: Date = .now) {
        defaults.set(date, forKey: Key.lastFixDate)
        defaults.set(deviceName, forKey: Key.lastFixDevice)
    }

    /// Re-reads values another process may have written.
    func synchronize() {
        CFPreferencesAppSynchronize(Self.domain as CFString)
    }

    static func post(_ name: Foundation.Notification.Name) {
        DistributedNotificationCenter.default().postNotificationName(name, object: nil, userInfo: nil, deliverImmediately: true)
    }
}
