# App Store launch readiness

A handoff for Claude Code on a real Mac: finish verifying the Mac App Store changes from the `feat/app-store-sandbox` branch, fix anything that fails, then prepare the upload. Read `CLAUDE.md` first. It covers the build, layout and conventions.

## What changed and why

| Change | Reason |
| --- | --- |
| `ENABLE_APP_SANDBOX = YES` for `AudioBalance` and `AudioBalanceAgent` | The App Store requires every executable to be sandboxed. |
| `AudioBalance/AudioBalance.entitlements` and `AudioBalanceAgent/AudioBalanceAgent.entitlements` add the app group `$(TeamIdentifierPrefix)dev.joshuapark.AudioBalance.shared` | A sandboxed agent can't read the app's defaults domain. Both processes now use the group suite. |
| `SharedSettings.appGroup` reads the group name from the process's entitlements (`SecTaskCopyValueForEntitlement`) | No team ID in code. Returns `nil` for unsigned builds (CI), which aren't sandboxed and fall back to the old domain. |
| `SharedSettings.migrateFromAppDomain()` runs in `AppModel.init` | Copies settings saved before sandboxing (the system moves them into the app container) into the group, once. |
| `SMAppService.agent(plistName:)` → `SMAppService.loginItem(identifier:)`. `LaunchAgents/` plist and "Embed Launch Agent" phase removed | Login items are the standard way to run a sandboxed helper. The launchd label is still `dev.joshuapark.AudioBalance.Agent`. |
| `AppModel.migrateLegacyAgent()` | Unregisters an old launch-agent registration and registers the login item if the agent was running. |
| `PrivacyInfo.xcprivacy` in both apps (UserDefaults reasons `CA92.1` and `1C8F.1`, no tracking, no data collected) | Required-reason API declaration for App Store Connect. |
| `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO` | Skips the export-compliance question on upload. |

## Status when handed off

Checked in a VM (no signing certificate, only "Apple Virtual Sound Device", which has no balance control):

- ✅ Unit tests pass, both unsigned (CI command) and ad-hoc signed.
- ✅ Sandboxed login item registers, runs, stops, and shows up in `launchctl print` under the same label. `testSwitchRegistersAndUnregistersAgent` and `testWindowReflectsAgentStoppedOutsideApp` pass. The setup was loosened temporarily for this run, and that change was reverted.
- ❌ **Not verified: settings reaching the agent through the app group.** With ad-hoc signing, macOS blocks the app's group-container writes:
  `Couldn't write values for keys (lockPoint) … setting preferences outside an application's container requires user-preference-write or file-write-data sandbox access`
  (sandboxd: `kTCCServiceSystemPolicyAppData … would require prompt`). The group has no team prefix under ad-hoc signing, so macOS can't tie it to the app. A build signed by team TCQ6328PP6 should be allowed. **This is the main thing left to prove.**
- ❌ Not run: `testAgentRestoresDriftedBalance`, `testLockPointIsAppliedToDevice` and `testStatusShowsBalanceWhileOff`. They need an output device with an adjustable balance.
- ⚠️ Rebuilding while the agent is registered can get launchd to kill the new agent once (`SIGKILL (Code Signature Invalid)`, "Launch Constraint Violation"). The next run was fine. Treat a first-run "Critical process Audio Balance Agent crashed" as this, and re-run with `test-without-building` before investigating.

## Verify on the real Mac

Prerequisites: Xcode signed in to team TCQ6328PP6, the default output set to a device with an adjustable balance (built-in speakers or AirPods), and accessibility access granted for UI testing.

1. Clear out older registrations, which may be from before the sandbox or ad-hoc builds:
   ```sh
   launchctl bootout gui/$UID/dev.joshuapark.AudioBalance.Agent 2>/dev/null
   sfltool dumpbtm | grep -A6 -i audiobalance   # look only; don't reset BTM without asking the user
   ```
2. Run everything, signed:
   ```sh
   xcodebuild -scheme AudioBalance -destination 'platform=macOS' -derivedDataPath build -allowProvisioningUpdates build test
   ```
   All 7 unit tests and 5 UI tests should pass. If one fails with the agent crashing on the first run after a build, re-run with `test-without-building`.
3. Check the signed entitlements. Expect the sandbox, the group `TCQ6328PP6.dev.joshuapark.AudioBalance.shared`, and no `Contents/Library/LaunchAgents`:
   ```sh
   A="build/Build/Products/Debug/Audio Balance.app"
   codesign -d --entitlements - "$A"
   codesign -d --entitlements - "$A/Contents/Library/LoginItems/Audio Balance Agent.app"
   ls "$A/Contents/Library"
   ```
   `ls` must show only `LoginItems`. A stale `LaunchAgents` folder from an old build means you should delete `build/` and rebuild.
4. Confirm the app group works end to end. Turn the app on, move the lock point slider, and watch:
   ```sh
   /usr/bin/log stream --predicate 'subsystem == "dev.joshuapark.AudioBalance"' --level info
   ```
   The agent should log `Lock point is now 0.25…` (not `0.5`) as the slider moves. Then check that there are no group-container denials:
   ```sh
   /usr/bin/log show --last 5m --predicate 'eventMessage CONTAINS "AudioBalance.shared"' | grep -iE "deny|rejecting|Couldn't write"
   ```
   The grep should print nothing. If denials show up with a team-signed build, fixes to consider, in order:
   - Confirm the entitlement string carries the team prefix, and that `SharedSettings.appGroup` resolves to it.
   - Switch to a `group.dev.joshuapark.AudioBalance` style group: register it in the developer portal and let automatic signing add it to both provisioning profiles. The `hasSuffix` match in `SharedSettings.appGroup` needs changing to match.
5. Check migration by hand (optional). With the old non-sandboxed build's settings in `~/Library/Preferences/dev.joshuapark.AudioBalance.plist` (lock point ≠ centre), launch the new build and check that the lock point carries over.
6. Check an Archive build. Product › Archive, or:
   ```sh
   xcodebuild -scheme AudioBalance -configuration Release -archivePath build/AudioBalance.xcarchive -allowProvisioningUpdates archive
   ```
   Then **Validate App** in the Organizer (App Store Connect distribution). Fix any validation errors (missing icon sizes, entitlements, privacy manifest) before uploading.

## Before submitting (App Store Connect)

- [ ] App record for bundle ID `dev.joshuapark.AudioBalance`. Category: Utilities (already `LSApplicationCategoryType`).
- [ ] Mac App Store provisioning profiles for the app and for `dev.joshuapark.AudioBalance.Agent`. Automatic signing creates them on archive.
- [ ] Set `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`, and bump the build number for each upload. Both targets share them from the project level.
- [ ] Screenshots of the settings window (light and dark) in the required Mac sizes.
- [ ] Privacy policy URL: host `PRIVACY.md`, e.g. the GitHub file URL. App Privacy answers: **Data Not Collected**.
- [ ] Review notes: "Audio Balance's background helper is a login item bundled in `Contents/Library/LoginItems` and registered with `SMAppService` only when the user turns on the main switch. It reads and sets the default output device's left–right balance through CoreAudio. There is no network access, audio capture, or data collection."
- [ ] Localized store metadata for de, es, fr, it, ja, ko, pt-BR, zh-Hans and zh-Hant, if the listing should match the app's localizations. "Audio Balance" isn't translated.
- [ ] Licence: the app is GPLv3. That's fine while every line is the owner's own work. Get a CLA or a licence exception before shipping outside contributions through the store.

## Conventions reminder

- Commits: Conventional Commits (see `CLAUDE.md`).
- New user-facing strings go in `Shared/Localizable.xcstrings` with all nine translations. Check them with `xcodebuild -exportLocalizations`.
- Don't edit `project.pbxproj` to list files (synchronized folders). Build settings are fine to edit.
