import Foundation
import Testing

struct BalancePolicyTests {
    @Test(arguments: [
        (current: Float(0.5), lock: Float(0.5), expected: false),
        (current: 0.51, lock: 0.5, expected: false),
        (current: 0.49, lock: 0.5, expected: false),
        (current: 0.515, lock: 0.5, expected: false),
        (current: 0.53, lock: 0.5, expected: true),
        (current: 0.3, lock: 0.5, expected: true),
        (current: 0.0, lock: 1.0, expected: true),
        (current: 0.305, lock: 0.3, expected: false),
    ])
    func needsCorrection(current: Float, lock: Float, expected: Bool) {
        #expect(BalancePolicy.needsCorrection(current: current, lock: lock) == expected)
    }

    @Test(arguments: [
        (value: Float(0.49), expected: Float(0.5)),
        (value: 0.515, expected: 0.5),
        (value: 0.5, expected: 0.5),
        (value: 0.47, expected: 0.47),
        (value: 0.6, expected: 0.6),
        (value: 1.2, expected: 1),
    ])
    func snapsNearCenter(value: Float, expected: Float) {
        #expect(BalancePolicy.snapped(value) == expected)
    }

    @Test func clampsToUnitRange() {
        #expect(BalancePolicy.clamped(-0.2) == 0)
        #expect(BalancePolicy.clamped(1.4) == 1)
        #expect(BalancePolicy.clamped(0.25) == 0.25)
    }

    @Test(arguments: [
        (value: Float(0.5), text: "Centered"),
        (value: 0.498, text: "Centered"),
        (value: 0.4, text: "20% Left"),
        (value: 0.0, text: "100% Left"),
        (value: 0.675, text: "35% Right"),
        (value: 1.0, text: "100% Right"),
    ])
    func describe(value: Float, text: String) {
        #expect(BalancePolicy.describe(value) == text)
    }
}

struct SharedSettingsTests {
    private func makeSettings() -> SharedSettings {
        let suite = "AudioBalanceTests.\(UUID().uuidString)"
        return SharedSettings(defaults: UserDefaults(suiteName: suite)!)
    }

    @Test func defaults() {
        let settings = makeSettings()
        #expect(settings.lockPoint == BalancePolicy.center)
        #expect(settings.notifyOnFix)
        #expect(settings.lastFixDate == nil)
    }

    @Test func lockPointIsClamped() {
        let settings = makeSettings()
        settings.lockPoint = 1.5
        #expect(settings.lockPoint == 1)
    }

    @Test func recordFix() {
        let settings = makeSettings()
        settings.recordFix(on: "AirPods Pro", at: Date(timeIntervalSince1970: 1_000))
        let date = Date(timeIntervalSince1970: 2_000)
        settings.recordFix(on: "AirPods Max", at: date)
        #expect(settings.lastFixDevice == "AirPods Max")
        #expect(settings.lastFixDate == date)
    }
}
