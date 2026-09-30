import AudioToolbox
import CoreAudio
import os

/// The CoreAudio property used to read and write a device's left–right balance.
nonisolated enum BalanceControl: Sendable {
    /// `kAudioHardwareServiceDeviceProperty_VirtualMainBalance` — what System Settings › Sound drives.
    case virtualMainBalance
    /// `kAudioDevicePropertyStereoPan` — fallback for devices without a virtual main balance.
    case stereoPan

    var selector: AudioObjectPropertySelector {
        switch self {
        case .virtualMainBalance: kAudioHardwareServiceDeviceProperty_VirtualMainBalance
        case .stereoPan: kAudioDevicePropertyStereoPan
        }
    }
}

/// Thin wrappers around the CoreAudio HAL calls Audio Balance needs.
nonisolated enum AudioOutput {
    static let logger = Logger(subsystem: "dev.joshuapark.AudioBalance", category: "AudioOutput")

    static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func defaultOutputDevice() -> AudioObjectID? {
        var address = address(kAudioHardwarePropertyDefaultOutputDevice)
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        guard status == noErr, deviceID != kAudioObjectUnknown else {
            logger.error("Could not get default output device: \(status)")
            return nil
        }
        return deviceID
    }

    static func name(of device: AudioObjectID) -> String? {
        var address = address(kAudioObjectPropertyName)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name)
        guard status == noErr, let name else { return nil }
        return name.takeRetainedValue() as String
    }

    /// The balance controls this device exposes that can also be written, in order of preference.
    static func balanceControls(of device: AudioObjectID) -> [BalanceControl] {
        [.virtualMainBalance, .stereoPan].filter { control in
            var address = address(control.selector, scope: kAudioDevicePropertyScopeOutput)
            guard AudioObjectHasProperty(device, &address) else { return false }
            var settable: DarwinBoolean = false
            return AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
        }
    }

    /// Current balance (0 = left, 0.5 = center, 1 = right) and the control it was read from.
    static func balance(of device: AudioObjectID) -> (value: Float, control: BalanceControl)? {
        for control in balanceControls(of: device) {
            var address = address(control.selector, scope: kAudioDevicePropertyScopeOutput)
            var value: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
            if status == noErr { return (value, control) }
            logger.debug("Reading \(String(describing: control)) failed: \(status)")
        }
        return nil
    }

    @discardableResult
    static func setBalance(_ value: Float, of device: AudioObjectID, using control: BalanceControl) -> OSStatus {
        var address = address(control.selector, scope: kAudioDevicePropertyScopeOutput)
        var value = Float32(value)
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
    }
}

/// Registers a CoreAudio property listener for its lifetime and removes it on deinit.
nonisolated final class PropertyListener: @unchecked Sendable {
    private let objectID: AudioObjectID
    private var address: AudioObjectPropertyAddress
    private let queue: DispatchQueue
    private let block: AudioObjectPropertyListenerBlock

    init?(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        queue: DispatchQueue = .main,
        handler: @escaping @Sendable () -> Void
    ) {
        self.objectID = objectID
        self.address = AudioOutput.address(selector, scope: scope)
        self.queue = queue
        self.block = { _, _ in handler() }
        let status = AudioObjectAddPropertyListenerBlock(objectID, &address, queue, block)
        guard status == noErr else {
            AudioOutput.logger.error("Adding listener for \(selector) on \(objectID) failed: \(status)")
            return nil
        }
    }

    deinit {
        AudioObjectRemovePropertyListenerBlock(objectID, &address, queue, block)
    }
}

/// Follows the system's default output device and reports changes to it and to its balance.
@MainActor
final class OutputObserver {
    enum Change {
        case device
        case balance
    }

    private(set) var device: AudioObjectID?
    private var deviceListener: PropertyListener?
    private var balanceListeners: [PropertyListener] = []
    private let onChange: @MainActor (Change) -> Void

    init(onChange: @escaping @MainActor (Change) -> Void) {
        self.onChange = onChange
    }

    func start() {
        deviceListener = PropertyListener(
            objectID: AudioObjectID(kAudioObjectSystemObject),
            selector: kAudioHardwarePropertyDefaultOutputDevice
        ) { [weak self] in
            MainActor.assumeIsolated { self?.bindToDefaultOutput() }
        }
        bindToDefaultOutput()
    }

    func stop() {
        deviceListener = nil
        balanceListeners = []
        device = nil
    }

    private func bindToDefaultOutput() {
        let newDevice = AudioOutput.defaultOutputDevice()
        if newDevice != device || balanceListeners.isEmpty {
            // Replacing the array releases, and therefore unregisters, the previous device's listeners.
            balanceListeners = newDevice.map { device in
                [BalanceControl.virtualMainBalance, .stereoPan].compactMap { control in
                    PropertyListener(
                        objectID: device,
                        selector: control.selector,
                        scope: kAudioDevicePropertyScopeOutput
                    ) { [weak self] in
                        MainActor.assumeIsolated { self?.onChange(.balance) }
                    }
                }
            } ?? []
            device = newDevice
        }
        onChange(.device)
    }
}
