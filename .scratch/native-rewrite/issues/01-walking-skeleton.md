# 01: Walking skeleton: add a task, see it in the backlog

**What to build:** The native macOS app launches. The user adds a task (name, estimated hours, energy cost, category, optional deadline) and sees it in the Backlog list; the task survives quitting and relaunching the app. This slice stands up the Xcode app target, the EmoKit Swift package that the app depends on, and local persistence. The data models must follow CloudKit's rules from day one (no unique constraints, every property optional or defaulted, optional relationships) so that turning on iCloud sync later (ticket 14) needs no migration.

**Blocked by:** None (can start immediately). Requires Xcode to be installed.

**Status:** done

- [x] Xcode project for the macOS app plus a local EmoKit Swift package; the app target depends on EmoKit
- [x] EmoKit builds and its tests run from the command line (`swift test`) as well as from Xcode
- [x] Task model carries the legacy fields: name, estimated hours, energy cost (low/medium/high), category (external commitment / self care / personal / leisure), deadline, recurrence, requires-transit + transit minutes, created/completed timestamps
- [x] Models satisfy CloudKit constraints (documented in a short comment or ADR)
- [x] User can add a task from the UI and it appears in the Backlog
- [x] Tasks persist across app relaunch
- [x] Domain logic lives in EmoKit, not in SwiftUI views
