# 26: iPhone Today: timeline, check-in and Plan Day

**What to build:** On iPhone, Today shows the day timeline with fixed events, task blocks, transit and the all-day strip. The daily check-in prompts on first open, and Plan Day fills the day. Editing is touch-first: tap to edit in a sheet, long-press then drag to move, drag the edge handles to resize, and swipe or menu actions for task blocks (complete, skip, pin, remove).

**Blocked by:** 25 (iPhone walking skeleton)

**Status:** done

- [x] Timeline renders the same `CalendarEngine` data and layout as the Mac
- [x] Check-in sheet and Plan Day (with summary message) work, including "check in first"
- [x] Touch editing: create (tap empty slot or + button), edit sheet, long-press drag to move with 15-min snapping, resize, delete
- [x] Task-block actions available via context menu
- [x] Previous/next day navigation (swipe or buttons)

## Comments

2026-11-13: The iPhone app now has a Today tab (`EmoPhone/PhoneTodayView.swift`, `PhoneDayTimelineView.swift`). The Mac and iPhone share `Shared/Calendar/DayScreen.swift`, which holds the Plan Day flow and summary text, Unschedule All, the pinned-conflict warning and the default start time for a new event. The event tints moved to `DisplayLabels.swift`. `EventEditor`, `CheckInSheet` and `TransitSheet` now have iPhone layouts, and `EventEditor(isNew:)` removes the event again if you cancel.

How touch editing works: tap a block to edit it in a sheet. Long-press to pick a block up and drag it (moves in 15-minute steps, with haptics). A selected block shows resize dots on its top and bottom edges and an ••• actions menu (TaskBlockActions, or Edit/Delete). Tap an empty slot to add an event there (Cancel removes it), or use + for an event or transit. To change day, use the chevrons, swipe the date header or tap "Today".

Change from the ticket: task-block actions are in the ••• menu on a selected block and in the edit sheet, not in a `.contextMenu`. On iOS a context menu also opens on long-press, so it would clash with long-press-to-drag.

Verified: the iPhone and Mac apps build, and EmoKit tests pass (140). In the iPhone 18 Pro simulator, the check-in prompt shows on first open over the Today timeline (screenshot checked).

Still to do: tap through the touch flows by hand (drag, resize, menu, tap to create, Plan Day after checking in). The first scroll position may not land on the current hour while the check-in sheet is showing.

2026-11-13 (later): After testing in the Simulator: drag works, though it's a bit shaky at times (fine for now). Task blocks now show quick-action icons on the block itself: complete, skip, pin and remove (`Shared/Calendar/BlockQuickActions.swift`). They show on the Mac on hover or selection, and on iPhone whenever the block has room. Other editable events get a delete icon. Still open: the user couldn't remove an in-progress block. Remove Block deletes the whole block, but Complete and Skip keep the part before now as history. We still need to know which one they used, and whether the past part should disappear or be shown as done.

2026-11-13: The user confirmed that blocks can now be removed, including one in progress (the current time falls inside it). Resolved.

2026-11-16: Ticked the boxes the comments above already cover (built, Simulator-tested by the user; task-block actions are in the ••• menu instead of a context menu, as noted).
