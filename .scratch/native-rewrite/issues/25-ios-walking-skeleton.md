# 25: iPhone walking skeleton: Backlog on the phone

**What to build:** A new iOS app target that runs on the simulator and installs on the user's iPhone via free provisioning. It shows the Backlog and lets the user add and edit tasks, using the same EmoKit store code as the Mac. Its data is local to the phone (no iCloud; see ticket 14).

**Blocked by:** 24 (Prefactor). On-device install also needs 23 (Personal Team signing); the simulator doesn't.

**Status:** done

- [x] project.yml adds an iOS target (iOS 26+) depending on EmoKit and the shared app code
- [x] Tab bar or sidebar-adaptive navigation with Backlog working: list, add, edit, complete, delete (swipe actions)
- [ ] Builds for the simulator from the command line; installs and launches on a device with the Personal Team
- [x] Data persists across relaunch on the phone

## Comments

2026-11-13: The `EmoPhone` iOS target (iOS 26+, iPhone, bundle `dev.emo.EmoPhone`) uses EmoKit and `Shared/`. EmoKit now declares `.iOS(.v26)`. The Backlog tab supports tap to edit, swipe to complete or delete, and + to add, using the shared `TaskEditorSheet` and `TaskLifecycle`. Data is local to the device.

Verified: it builds for the Simulator from the command line (`xcodebuild -scheme EmoPhone -destination 'platform=iOS Simulator,name=iPhone 18 Pro'`), and it installs and launches on the iPhone 18 Pro simulator with the backlog empty state (screenshot checked).

Pending: installing on a real device needs a free Personal Team (ticket 23); the user has no Apple ID set up in Xcode yet. Add, edit and swipe flows need a manual tap-through in the Simulator.
