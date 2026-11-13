# 25: iPhone walking skeleton: Backlog on the phone

**What to build:** A new iOS app target that runs on the simulator and installs on the user's iPhone via free provisioning. It shows the Backlog and lets the user add and edit tasks, using the same EmoKit store code as the Mac. Its data is local to the phone (no iCloud; see ticket 14).

**Blocked by:** 24 (Prefactor). On-device install also needs 23 (Personal Team signing); the simulator doesn't.

**Status:** ready-for-agent

- [ ] project.yml adds an iOS target (iOS 26+) depending on EmoKit and the shared app code
- [ ] Tab bar or sidebar-adaptive navigation with Backlog working: list, add, edit, complete, delete (swipe actions)
- [ ] Builds for the simulator from the command line; installs and launches on a device with the Personal Team
- [ ] Data persists across relaunch on the phone
