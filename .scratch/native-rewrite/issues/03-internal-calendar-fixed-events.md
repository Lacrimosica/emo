# 03: Internal calendar: local fixed events on the Today timeline

**What to build:** A day timeline view (Today) backed by Emo's own internal calendar. The user can create, move, resize and delete fixed events owned by Emo. This internal calendar is the source of truth that the scheduler and every integration feed into; it must not depend on any third-party type.

**Blocked by:** 01 (Walking skeleton)

**Status:** done (pending manual UI check, see Comments)

- [x] Internal calendar event model with kinds (fixed, task block, transit, buffer), start/end, title, notes, an origin (local vs. linked to an external source) and a locked flag
- [x] Today shows a vertical timeline of the selected day with events laid out by time
- [ ] User can create a fixed event, edit its title/time, drag to move, drag to resize, and delete it
- [x] Navigating to previous/next day works
- [x] Events persist across relaunch
- [x] Calendar engine API in EmoKit is the only path that writes internal events (views call it, never the store directly)

## Comments

2026-11-13: Implemented. Verified by driving the real app via accessibility: ⌘E creates a 1-hour event at the next quarter hour; the editor popover opens, renames and saves; Delete in the editor removes the event; the store reflects each change. Engine, day query (cross-midnight), validation, linked-event read-only guard, snapping and overlap layout are unit-tested.

Not verifiable with synthetic input. Needs a manual check before ticking the "create, edit, move, resize, delete" box:
- double-click on empty timeline creates an event
- drag an event to move it (15-minute snapping)
- drag top/bottom edge to resize
- click an event, then press Delete
