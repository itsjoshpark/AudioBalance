import AppKit
import CoreAudio
import Observation
import os
import ServiceManagement

/// State behind the settings window: whether the agent is on, the shared settings, and live status.
@Observable
final class AppModel {
    enum AgentState: Equatable {
        /// Registered with launchd and running.
        case running
        /// Registered, but launchd isn't running it (e.g. after `launchctl bootout`).
        case notRunning
        /// Registered, but the user turned it off in System Settings › Login Items.
        case requiresApproval
        case off
    }

    private(set) var agentState: AgentState = .off
    private(set) var isChangingAgent = false
    private(set) var agentError: String?

    var lockPoint: Double {
        didSet {
            guard lockPoint != oldValue else { return }
            settings.lockPoint = Float(lockPoint)
            SharedSettings.post(SharedSettings.Notification.settingsChanged)
        }
    }

    var notifyOnFix: Bool {
        didSet {
            guard notifyOnFix != oldValue else { return }
            settings.notifyOnFix = notifyOnFix
            SharedSettings.post(SharedSettings.Notification.settingsChanged)
        }
    }

    private(set) var deviceName: String?
    private(set) var currentBalance: Float?
    private(set) var lastFixDate: Date?
    private(set) var lastFixDevice: String?

    var isOn: Bool { agentState == .running }

    @ObservationIgnored private let logger = Logger(subsystem: "dev.joshuapark.AudioBalance", category: "AppModel")
    @ObservationIgnored private let settings = SharedSettings()
    @ObservationIgnored private let service = SMAppService.loginItem(identifier: SharedSettings.agentBundleIdentifier)
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var runningAppsObservation: NSKeyValueObservation?
    @ObservationIgnored private lazy var outputObserver = OutputObserver { [weak self] _ in
        self?.refreshOutput()
    }

    init() {
        settings.migrateFromAppDomain()
        lockPoint = Double(settings.lockPoint)
        notifyOnFix = settings.notifyOnFix
        observeSystem()
        outputObserver.start()
        refresh()
    }

    // MARK: - Agent

    /// Re-derives everything from the system instead of trusting cached state, so changes made in
    /// System Settings or with `launchctl` show up when the window reappears.
    func refresh() {
        refreshAgentState()
        refreshFixHistory()
        refreshOutput()
    }

    func setOn(_ on: Bool) {
        guard !isChangingAgent else { return }
        isChangingAgent = true
        agentError = nil
        Task {
            defer {
                isChangingAgent = false
                refreshAgentState()
            }
            do {
                if on {
                    // Unregistering first restarts an agent launchd knows about but isn't running.
                    if service.status == .enabled { try await service.unregister() }
                    try service.register()
                    if service.status == .enabled { await waitForAgent(running: true) }
                } else {
                    try await service.unregister()
                    await waitForAgent(running: false)
                }
            } catch {
                logger.error("Changing agent registration failed: \(error.localizedDescription)")
                agentError = error.localizedDescription
            }
        }
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func refreshAgentState() {
        agentState = switch service.status {
        case .enabled: isAgentRunning ? .running : .notRunning
        case .requiresApproval: .requiresApproval
        case .notRegistered, .notFound: .off
        @unknown default: .off
        }
    }

    private var isAgentRunning: Bool {
        // A just-terminated agent can still be listed while its termination notification is delivered.
        NSRunningApplication.runningApplications(withBundleIdentifier: SharedSettings.agentBundleIdentifier)
            .contains { !$0.isTerminated }
    }

    /// launchd starts and stops the agent asynchronously; give it a moment before reporting state.
    private func waitForAgent(running: Bool) async {
        for _ in 0..<20 where isAgentRunning != running {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    // MARK: - Status

    private func refreshFixHistory() {
        settings.synchronize()
        lastFixDate = settings.lastFixDate
        lastFixDevice = settings.lastFixDevice
    }

    private func refreshOutput() {
        guard let device = outputObserver.device else {
            deviceName = nil
            currentBalance = nil
            return
        }
        deviceName = AudioOutput.name(of: device)
        currentBalance = AudioOutput.balance(of: device)?.value
    }

    private func observeSystem() {
        // Workspace launch/terminate notifications skip UI-element apps like the agent; the
        // running-applications list covers every process LaunchServices knows about.
        runningAppsObservation = NSWorkspace.shared.observe(\.runningApplications) { [weak self] _, _ in
            DispatchQueue.main.async { self?.refreshAgentState() }
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        })
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: SharedSettings.Notification.balanceFixed, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshFixHistory() }
        })
    }
}
