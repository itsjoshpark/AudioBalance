import Foundation
import Security

/// Settings shared between the settings app and the background agent.
///
/// Both processes are sandboxed, so they share preferences through the ``appGroup`` container.
/// After writing, the app posts ``Notification/settingsChanged`` so the agent reloads immediately,
/// and the agent posts ``Notification/balanceFixed`` after each correction.
nonisolated struct SharedSettings: @unchecked Sendable {
    static let domain = "dev.joshuapark.AudioBalance"
    static let agentBundleIdentifier = "dev.joshuapark.AudioBalance.Agent"
    /// The app group shared by the app and the agent, read from this process's entitlements
    /// (`$(TeamIdentifierPrefix)dev.joshuapark.AudioBalance.shared`), so the team prefix comes from
    /// signing. `nil` in unsigned builds, which aren't sandboxed.
    static let appGroup: String? = {
        guard let task = SecTaskCreateFromSelf(nil),
              let groups = SecTaskCopyValueForEntitlement(task, "com.apple.security.application-groups" as CFString, nil)
                as? [String]
        else { return nil }
        return groups.first { $0.hasSuffix("\(domain).shared") }
    }()

    /// The preferences domain both processes use.
    static var suiteName: String { appGroup ?? domain }

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
        } else if Bundle.main.bundleIdentifier == Self.suiteName {
            // Unsigned builds fall back to the app's own domain, and a suite can't be named after it.
            self.defaults = .standard
        } else {
            self.defaults = UserDefaults(suiteName: Self.suiteName) ?? .standard
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
        CFPreferencesAppSynchronize(Self.suiteName as CFString)
    }

    /// Copies settings saved before the app was sandboxed, when they lived in the app's own
    /// domain (now migrated into its container), into the app group. Runs once.
    func migrateFromAppDomain() {
        let keys = [Key.lockPoint, Key.notifyOnFix, Key.lastFixDate, Key.lastFixDevice]
        guard let appGroup = Self.appGroup else { return }
        let current = defaults.persistentDomain(forName: appGroup) ?? [:]
        guard keys.allSatisfy({ current[$0] == nil }),
              let old = UserDefaults.standard.persistentDomain(forName: Self.domain) else { return }
        for key in keys {
            if let value = old[key] { defaults.set(value, forKey: key) }
        }
    }

    static func post(_ name: Foundation.Notification.Name) {
        DistributedNotificationCenter.default().postNotificationName(name, object: nil, userInfo: nil, deliverImmediately: true)
    }
}
