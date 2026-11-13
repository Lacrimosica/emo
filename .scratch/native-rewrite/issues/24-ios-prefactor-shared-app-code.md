# 24: Prefactor: share app-level code between Mac and iPhone

**What to build:** Before adding an iPhone target, move the platform-neutral app code out of the Mac target so both apps can use it: the Calendar and Reminders sync services, AI provider selection, display labels and colours, and the clarifier/chat state. Mac-only pieces (NSCursor resize handles, the Settings scene, menu commands, NSWorkspace links) stay in the Mac target or behind `#if os(macOS)`. The Mac app behaves exactly as before.

**Blocked by:** None (can start immediately). Coordinate with any in-flight work on the Integrations settings and Reminders files (tickets 17–22).

**Status:** done

- [x] Shared app code lives in one place compiled into both targets (e.g. an `EmoAppKit` folder or library), with no AppKit imports
- [x] EmoKit stays free of UI code; all its tests still pass
- [x] The Mac app builds and works unchanged (smoke-test Today, Week, Backlog, Settings and sync)

## Comments

2026-11-13: Platform-neutral app code now lives in `apple/Shared/`, a synced folder compiled into both targets:
- Integrations: the Calendar and Reminders sync services.
- Assistant: AI provider selection, dictation and the chat sheet.
- Tasks: the task editor, pin sheet and check-in.
- Calendar: the event editor, task-block actions and transit sheet.
- Settings: AI settings, model picker and write-back section.
- Display labels and the energy badge.

The Mac target keeps the AppKit-dependent pieces (the timeline's resize cursors, Integrations settings with NSWorkspace links, the Settings scene and menu commands) and the Mac-shaped views. Files were moved with `git mv`. The Mac app builds unchanged, and all 139 EmoKit tests pass. Dictation sets up an AVAudioSession on iOS; the chat's fixed size is Mac-only.
