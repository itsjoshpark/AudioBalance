import AppKit
import CoreAudio
import XCTest

/// End-to-end tests that drive the real settings window, then check the result in launchd and
/// CoreAudio.
///
/// These register the agent with the system and change the default output device's balance.
/// Xcode sandboxes the UI test runner, so it can't read the app's preferences. Settings are
/// checked through the window instead, and each test ends with the lock point centered, the
/// agent turned off and the device balance restored. Corrections made during a run stay in the
/// app's history.
final class AudioBalanceUITests: XCTestCase {
    private var app: XCUIApplication!
    private var device: AudioObjectID!
    private var savedBalance: (value: Float, control: BalanceControl)!

    override func setUpWithError() throws {
        continueAfterFailure = false
        let device = try XCTUnwrap(AudioOutput.defaultOutputDevice(), "No default output device")
        savedBalance = try XCTUnwrap(
            AudioOutput.balance(of: device),
            "The default output device has no adjustable balance"
        )
        self.device = device

        app = XCUIApplication()
        app.launch()
        XCTAssertTrue(agentSwitch.waitForExistence(timeout: 5))
        if isSwitchOn { setSwitch(on: false) }
    }

    override func tearDownWithError() throws {
        defer {
            if let device, let savedBalance {
                AudioOutput.setBalance(savedBalance.value, of: device, using: savedBalance.control)
            }
        }
        guard let app, app.state == .runningForeground || app.state == .runningBackground else { return }
        if !isSwitchOn { setSwitch(on: true) }
        if lockPointLabel != "Centered" {
            element("centerButton").click()
            wait(until: "lock point is centered") { self.lockPointLabel == "Centered" }
        }
        setSwitch(on: false)
        app.terminate()
    }

    // MARK: - Tests

    func testSwitchRegistersAndUnregistersAgent() {
        setSwitch(on: true)
        XCTAssertEqual(launchctl("print", agentService), 0, "launchd doesn't know about the agent")

        setSwitch(on: false)
        XCTAssertNotEqual(launchctl("print", agentService), 0, "launchd still has the agent")
    }

    func testWindowReflectsAgentStoppedOutsideApp() {
        setSwitch(on: true)

        XCTAssertEqual(launchctl("bootout", agentService), 0)
        wait(until: "agent stops") { !self.isAgentRunning }
        wait(until: "switch shows off") { !self.isSwitchOn }
        let restart = element("restartButton")
        XCTAssertTrue(restart.waitForExistence(timeout: 5), "No not-running notice")

        restart.click()
        wait(until: "agent restarts") { self.isAgentRunning }
        wait(until: "switch shows on") { self.isSwitchOn }
        XCTAssertFalse(restart.exists)
    }

    func testAgentRestoresDriftedBalance() {
        setSwitch(on: true)
        wait(until: "device is at the lock point") { self.isDeviceBalance(near: 0.5) }
        let deviceName = AudioOutput.name(of: device)

        XCTAssertEqual(AudioOutput.setBalance(0.3, of: device, using: savedBalance.control), noErr)
        wait(until: "balance returns to center") { self.isDeviceBalance(near: 0.5) }
        wait(until: "correction is shown") { self.text(of: self.element("lastCorrectionDevice")) == deviceName }
    }

    func testLockPointIsAppliedToDevice() {
        setSwitch(on: true)

        element("lockPointSlider").adjust(toNormalizedSliderPosition: 0.25)
        wait(until: "lock point moves left") { self.lockPointLabel.hasSuffix("Left") }
        wait(until: "device follows lock point") {
            let current = AudioOutput.balance(of: self.device)?.value ?? 0.5
            return current < 0.45 && self.currentBalanceLabel == self.lockPointLabel
        }

        element("centerButton").click()
        wait(until: "lock point is centered") { self.lockPointLabel == "Centered" }
        wait(until: "device is centered") { self.isDeviceBalance(near: 0.5) }
    }

    func testStatusShowsBalanceWhileOff() {
        XCTAssertFalse(isSwitchOn)

        XCTAssertEqual(AudioOutput.setBalance(0.3, of: device, using: savedBalance.control), noErr)
        wait(until: "status shows the drift") { self.currentBalanceLabel == "40% Left" }
        XCTAssertTrue(isDeviceBalance(near: 0.3), "Something corrected the balance while off")

        XCTAssertEqual(AudioOutput.setBalance(0.5, of: device, using: savedBalance.control), noErr)
        wait(until: "status shows centered") { self.currentBalanceLabel == "Centered" }
    }

    // MARK: - Helpers

    private let agentService = "gui/\(getuid())/\(SharedSettings.agentBundleIdentifier)"

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private var agentSwitch: XCUIElement { element("agentSwitch") }

    private var isSwitchOn: Bool {
        switch agentSwitch.value {
        case let number as NSNumber: number.boolValue
        case let string as String: string == "1"
        default: false
        }
    }

    private var lockPointLabel: String { text(of: element("lockPointValue")) }
    private var currentBalanceLabel: String { text(of: element("currentBalance")) }

    /// Static text on macOS exposes its string as the element's value rather than its label.
    private func text(of element: XCUIElement) -> String {
        (element.value as? String) ?? element.label
    }

    private var isAgentRunning: Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: SharedSettings.agentBundleIdentifier)
            .contains { !$0.isTerminated }
    }

    private func isDeviceBalance(near value: Float) -> Bool {
        guard let current = AudioOutput.balance(of: device)?.value else { return false }
        return abs(current - value) < BalancePolicy.tolerance
    }

    private func setSwitch(on: Bool, file: StaticString = #filePath, line: UInt = #line) {
        agentSwitch.click()
        wait(until: "switch turns \(on ? "on" : "off")", file: file, line: line) { self.isSwitchOn == on }
        wait(until: "agent \(on ? "starts" : "stops")", file: file, line: line) { self.isAgentRunning == on }
    }

    private func wait(
        until description: String,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @escaping () -> Bool
    ) {
        let predicate = NSPredicate { _, _ in MainActor.assumeIsolated { condition() } }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        expectation.expectationDescription = description
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        if result != .completed {
            XCTFail("Timed out waiting until \(description)", file: file, line: line)
        }
    }

    @discardableResult
    private func launchctl(_ arguments: String...) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            XCTFail("Running launchctl failed: \(error)")
            return -1
        }
    }
}
