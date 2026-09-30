import os
import UserNotifications

/// Posts "balance restored" notifications from the agent.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private let logger = Logger(subsystem: "dev.joshuapark.AudioBalance", category: "Notifier")
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert]) { [logger] granted, error in
            if let error {
                logger.error("Notification authorization failed: \(error.localizedDescription)")
            } else if !granted {
                logger.info("Notifications are not allowed")
            }
        }
    }

    func postBalanceRestored(deviceName: String?, lockPoint: Float) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Balance Restored")
        let device = deviceName ?? String(localized: "your output device")
        content.body = if lockPoint == BalancePolicy.center {
            String(localized: "Audio Balance re-centered \(device).")
        } else {
            String(localized: "Audio Balance set \(device) back to \(BalancePolicy.describe(lockPoint)).")
        }
        // A fixed identifier replaces the previous banner instead of stacking up.
        let request = UNNotificationRequest(identifier: "balance-restored", content: content, trigger: nil)
        center.add(request) { [logger] error in
            if let error { logger.error("Posting notification failed: \(error.localizedDescription)") }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}
