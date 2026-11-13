# 24: Prefactor: share app-level code between Mac and iPhone

**What to build:** Before adding an iPhone target, move the platform-neutral app code out of the Mac target so both apps can use it: the Calendar and Reminders sync services, AI provider selection, display labels and colours, and the clarifier/chat state. Mac-only pieces (NSCursor resize handles, the Settings scene, menu commands, NSWorkspace links) stay in the Mac target or behind `#if os(macOS)`. The Mac app behaves exactly as before.

**Blocked by:** None (can start immediately). Coordinate with any in-flight work on the Integrations settings and Reminders files (tickets 17–22).

**Status:** ready-for-agent

- [ ] Shared app code lives in one place compiled into both targets (e.g. an `EmoAppKit` folder or library), with no AppKit imports
- [ ] EmoKit stays free of UI code; all its tests still pass
- [ ] The Mac app builds and works unchanged (smoke-test Today, Week, Backlog, Settings and sync)
