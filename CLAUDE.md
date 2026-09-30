# Audio Balance

A macOS 15+ app that keeps the output device's left–right balance locked (AirPods often drift). It's a SwiftUI settings app plus a background agent that is bundled inside the app and registered with `SMAppService`.

## Build & test

```sh
xcodebuild -scheme AudioBalance -destination 'platform=macOS' -derivedDataPath build -allowProvisioningUpdates build test
```

`AudioBalanceUITests` drive the real window. They register and unregister the agent with launchd, change the default output device's balance, and leave the lock point centred. The output device must have an adjustable balance. Run only the unit tests with `-only-testing:AudioBalanceTests`. CI (`.github/workflows/ci.yml`, `macos-26`) runs only the unit tests, unsigned (`CODE_SIGNING_ALLOWED=NO`). Hosted runners can't run the UI tests.

Agent logs: `/usr/bin/log stream --predicate 'subsystem == "dev.joshuapark.AudioBalance"' --level debug`
Agent state: `launchctl print gui/$UID/dev.joshuapark.AudioBalance.Agent`

## Layout

- `AudioBalance/`: settings app (`Audio Balance.app`). It holds `AppModel` (agent registration via `SMAppService.agent`, shared settings, live status) and `SettingsView`.
- `AudioBalanceAgent/`: background agent (`Audio Balance Agent.app`, `LSUIElement`). `BalanceMonitor` debounces CoreAudio change events and writes the lock point back. `Notifier` posts notifications.
- `Shared/`: compiled into both apps and the tests.
  - `AudioOutput`: CoreAudio HAL wrappers. `PropertyListener` removes its listener on deinit. `OutputObserver` follows the default output device.
  - `BalancePolicy`: pure logic.
  - `SharedSettings`: the `dev.joshuapark.AudioBalance` defaults domain plus distributed notifications.
- `Icon/AppIcon.icon`: Icon Composer icon used by both apps.
- `LaunchAgents/dev.joshuapark.AudioBalance.Agent.plist`: copied to `Contents/Library/LaunchAgents`. The agent app is copied to `Contents/Library/LoginItems`.

The project uses Xcode's synchronized folders (objectVersion 77). Add files by creating them in the right folder; don't edit `project.pbxproj` to list files.

## Conventions

- Minimum macOS 15, Swift 5 mode with MainActor default isolation. CoreAudio helpers are `nonisolated`.
- The settings window must re-derive agent state from `SMAppService.status` and the running agent process, never from cached values. The agent can be changed outside the app.
- Keep `BalancePolicy` free of CoreAudio so it stays unit-testable. Add tests in `AudioBalanceTests/` (Swift Testing).
- Give new controls an `accessibilityIdentifier` for the UI tests.
  - The UI test runner is sandboxed. It can't read the app's defaults, but it can use CoreAudio and `launchctl`.
  - On macOS, static text exposes its string as the element's `value`.
- Watch the agent process with KVO on `NSWorkspace.runningApplications`. Workspace launch/terminate notifications don't fire for UI-element apps.
- Not sandboxed. The agent reads the app's defaults domain directly.
- Localization: every user-facing string lives in `Shared/Localizable.xcstrings` (one catalog shared by both apps).
  - Add translations for all of de, es, fr, it, ja, ko, pt-BR, zh-Hans and zh-Hant with each new string.
  - Use Apple's own wording for System Settings names. Take it from the OS `.loctable` files, e.g. `/System/Library/ExtensionKit/Extensions/LoginItems.appex/Contents/Resources/Localizable.loctable`.
  - Check coverage with `xcodebuild -exportLocalizations`.
  - "Audio Balance" is never translated.

## Commits

Use [Conventional Commits](https://www.conventionalcommits.org/): `type(scope): summary`.

- Types: `feat`, `fix`, `refactor`, `perf`, `test`, `docs`, `build`, `ci`, `chore`.
- Scopes (optional): `app`, `agent`, `shared`, `icon`, `project`.
- Summary in the imperative, lowercase, no trailing period, 72 characters or fewer. Mark breaking changes with `!` or a `BREAKING CHANGE:` footer.
