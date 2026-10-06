# Audio Balance

A macOS 15+ app that keeps the output device's left–right balance locked (AirPods often drift). It's a SwiftUI settings app plus a background agent that is bundled inside the app and registered as a login item with `SMAppService`. Distributed through the Mac App Store, so both apps are sandboxed.

## Build & test

```sh
xcodebuild -scheme AudioBalance -destination 'platform=macOS' -derivedDataPath build -allowProvisioningUpdates build test
```

The build must be signed by the team (the Development certificate for TCQ6328PP6). Ad-hoc signing (`CODE_SIGN_IDENTITY=-`) builds and launches, but macOS blocks writes to the app group container, so the agent never sees setting changes.

Switching one Mac between an Xcode build (Apple Development) and the App Store build leaves the old login item record in Background Task Management, along with its code requirement. Until macOS replaces that record, the kernel kills the other build's agent with `Launch Constraint Violation`, and the app shows "registered but isn't running". Wait several seconds for the new "login item added" notification, then turn the switch on again. To check: `/usr/bin/log show --last 10m --predicate 'eventMessage CONTAINS "Launch Constraint"'`.

`AudioBalanceUITests` drive the real window. They register and unregister the agent with launchd, change the default output device's balance, and leave the lock point centred. The output device must have an adjustable balance. Run only the unit tests with `-only-testing:AudioBalanceTests`. CI (`.github/workflows/ci.yml`, `macos-26`) runs only the unit tests, unsigned (`CODE_SIGNING_ALLOWED=NO`). Hosted runners can't run the UI tests.

Agent logs: `/usr/bin/log stream --predicate 'subsystem == "dev.joshuapark.AudioBalance"' --level debug`
Agent state: `launchctl print gui/$UID/dev.joshuapark.AudioBalance.Agent`

## Release

The 🚀 Release workflow (`.github/workflows/release.yml`, run manually from main) bumps the version, archives and signs with the App Store Connect API key, uploads the build to App Store Connect, tags `vX.Y.Z` and publishes a GitHub release.

1. Replace `release-notes/next.md` with the notes (keep the `- New:` / `- Changed:` / `- Fixed:` shape of `release-notes/TEMPLATE.md`). The workflow refuses to run with the unedited template, then archives the file as `release-notes/<version>.md`.
2. Run the workflow with a release type. Try a dry run first: it archives and exports the `.pkg` as an artifact but uploads nothing.
3. Submit the build for review, with its "What's New" text, in App Store Connect.

The version is `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in the project-level Debug and Release settings of `project.pbxproj`. Don't set them per target. The workflow passes the new version to `xcodebuild` and commits it back to `project.pbxproj` after the release. The build number is the commit count. `scripts/project-version.sh` (shared with FrontRow) and `scripts/bump-version.sh` have tests (`scripts/*.test.sh`) that CI runs.

## Layout

- `AudioBalance/`: settings app (`Audio Balance.app`). It holds `AppModel` (agent registration via `SMAppService.loginItem`, shared settings, live status) and `SettingsView`.
- `AudioBalanceAgent/`: background agent (`Audio Balance Agent.app`, `LSUIElement`). `BalanceMonitor` debounces CoreAudio change events and writes the lock point back. `Notifier` posts notifications.
- `Shared/`: compiled into both apps and the tests.
  - `AudioOutput`: CoreAudio HAL wrappers. `PropertyListener` removes its listener on deinit. `OutputObserver` follows the default output device.
  - `BalancePolicy`: pure logic.
  - `SharedSettings`: the `$(TeamIdentifierPrefix)dev.joshuapark.AudioBalance.shared` app group defaults plus distributed notifications. The group name is read from the process's entitlements at runtime.
- `Icon/AppIcon.icon`: Icon Composer icon used by both apps.
- `*.entitlements` (app sandbox and app group) and `PrivacyInfo.xcprivacy` in each app folder.
- The agent app is copied to `Contents/Library/LoginItems`. Its launchd label is its bundle identifier.

The project uses Xcode's synchronized folders (objectVersion 77). Add files by creating them in the right folder; don't edit `project.pbxproj` to list files.

## Conventions

- Minimum macOS 15, Swift 5 mode with MainActor default isolation. CoreAudio helpers are `nonisolated`.
- The settings window must re-derive agent state from `SMAppService.status` and the running agent process, never from cached values. The agent can be changed outside the app.
- Keep `BalancePolicy` free of CoreAudio so it stays unit-testable. Add tests in `AudioBalanceTests/` (Swift Testing).
- Give new controls an `accessibilityIdentifier` for the UI tests.
  - The UI test runner is sandboxed. It can't read the app's defaults, but it can use CoreAudio and `launchctl`.
  - On macOS, static text exposes its string as the element's `value`.
- Watch the agent process with KVO on `NSWorkspace.runningApplications`. Workspace launch/terminate notifications don't fire for UI-element apps.
- Both apps are sandboxed (Mac App Store). They share settings only through the app group, and distributed notifications must not carry a `userInfo`. Keep both entitlements files in sync.
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
