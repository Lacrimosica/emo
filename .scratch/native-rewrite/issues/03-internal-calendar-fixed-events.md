# 03: Internal calendar: local fixed events on the Today timeline

**What to build:** A day timeline view (Today) backed by Emo's own internal calendar. The user can create, move, resize and delete fixed events owned by Emo. This internal calendar is the source of truth that the scheduler and every integration feed into; it must not depend on any third-party type.

**Blocked by:** 01 (Walking skeleton)

**Status:** ready-for-agent

- [ ] Internal calendar event model with kinds (fixed, task block, transit, buffer), start/end, title, notes, an origin (local vs. linked to an external source) and a locked flag
- [ ] Today shows a vertical timeline of the selected day with events laid out by time
- [ ] User can create a fixed event, edit its title/time, drag to move, drag to resize, and delete it
- [ ] Navigating to previous/next day works
- [ ] Events persist across relaunch
- [ ] Calendar engine API in EmoKit is the only path that writes internal events (views call it, never the store directly)
