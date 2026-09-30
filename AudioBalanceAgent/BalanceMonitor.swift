import CoreAudio
import os

/// Watches the default output device and puts its balance back to the lock point whenever it drifts.
final class BalanceMonitor {
    private let logger = Logger(subsystem: "dev.joshuapark.AudioBalance", category: "BalanceMonitor")
    private let settings: SharedSettings
    private let notifier: Notifier
    private lazy var observer = OutputObserver { [weak self] change in
        self?.outputDidChange(change)
    }
    private var pendingCheck: Task<Void, Never>?

    init(settings: SharedSettings, notifier: Notifier) {
        self.settings = settings
        self.notifier = notifier
    }

    func start() {
        logger.info("Starting balance monitor")
        observer.start()
    }

    /// Applies a new lock point right away. This is the user's own choice, so it isn't
    /// counted or announced as a correction.
    func lockPointDidChange() {
        logger.info("Lock point is now \(self.settings.lockPoint)")
        scheduleCheck(countsAsFix: false)
    }

    private func outputDidChange(_ change: OutputObserver.Change) {
        logger.debug("Output changed: \(String(describing: change))")
        scheduleCheck(countsAsFix: true)
    }

    private func scheduleCheck(countsAsFix: Bool) {
        pendingCheck?.cancel()
        pendingCheck = Task { [weak self] in
            try? await Task.sleep(for: BalancePolicy.debounce)
            guard !Task.isCancelled else { return }
            self?.checkAndFix(countsAsFix: countsAsFix)
        }
    }

    private func checkAndFix(countsAsFix: Bool) {
        guard let device = observer.device else { return }
        guard let (current, control) = AudioOutput.balance(of: device) else {
            logger.info("Output device \(device) has no adjustable balance")
            return
        }
        let lock = settings.lockPoint
        guard BalancePolicy.needsCorrection(current: current, lock: lock) else { return }

        let status = AudioOutput.setBalance(lock, of: device, using: control)
        guard status == noErr else {
            logger.error("Setting balance to \(lock) on \(device) failed: \(status)")
            return
        }
        let deviceName = AudioOutput.name(of: device)
        logger.info("Balance on \(deviceName ?? "unknown device", privacy: .public) moved from \(current) to \(lock)")
        guard countsAsFix else { return }

        settings.recordFix(on: deviceName)
        SharedSettings.post(SharedSettings.Notification.balanceFixed)
        if settings.notifyOnFix {
            notifier.postBalanceRestored(deviceName: deviceName, lockPoint: lock)
        }
    }
}
