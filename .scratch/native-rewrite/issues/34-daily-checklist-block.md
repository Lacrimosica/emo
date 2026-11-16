# 34: Daily checklist as one block

**What to build:** Items from routine lists ("CHECKLIST DAILY") are planned as one combined block a day
instead of a short block per item, and they're daily whether or not they repeat in Reminders. Ticking an
item means "done today", not "done for good".

**Blocked by:** 17 (list roles), 31 (ongoing tasks)

**Status:** in-review (pending manual check, see Comments)

Decided with the user (2026-11-16): one combined block; lists hold a mix of repeating and plain items, so
Emo treats every item as daily itself.

- One Emo-managed checklist task per routine list area (`TaskItem.isChecklist`): ongoing, 7 sessions a week,
  session length = sum of its open items (rounded up to 5 min). Created, resized and removed on each Reminders
  sync. Named "Daily checklist" (or "Checklist: <area>").
- Routine items: 5 min each by default, never planned on their own.
- Done today: ticking an item in Emo, or a completion seen in Reminders (by its completion date), logs a
  `TaskSession` for that item and day; the item stays open. When every item of a checklist is done for a
  day, the checklist's session for that day is logged and its block cleared.
- A routine reminder that stays completed in Reminders drops out of Emo after the 30-day lookback, as now.
- Emo doesn't tick the reminder in Reminders (no completion write-back yet).
- Reminders tags (`#tag`) aren't readable through EventKit; roles come from list names only.

- [x] Checklist task maintained from routine items
- [x] Item "done today" from Emo and from Reminders; all done → checklist done for the day
- [x] Backlog shows routine items as done today

## Comments

2026-11-16: Built.
- `TaskItem.isChecklist` / `isRoutineItem`; routine items are never plannable on their own and aren't flagged "Needs context".
- `RoutineChecklist` (EmoKit/Backlog): `sync` runs after every Reminders reconcile (and on removeAll); `markDone` logs a
  `TaskSession` per item and day and, once all are done, `TaskLifecycle.logSession` on the checklist.
- `TaskLifecycle.complete` on a routine item routes to `markDone`; the reconciler uses the reminder's `completionDate`
  (new `ExternalReminder.completedAt`).
- Backlog (Mac): a "Checklist items" section with done-today ticks; iPhone rows show the tick. The checklist task hides
  Stop / Clarify / Delete (it follows the list).
- A sync doesn't re-plan: a new or resized checklist lands on the calendar at the next Plan Day (same as new reminders).
- Not done: un-ticking an item for today; listing the items inside the checklist block's sheet; writing completion back
  to Reminders.
- Manual check: with CHECKLIST DAILY selected in Settings › Integrations, Plan Day shows one "Daily checklist" block;
  ticking every item in the backlog clears it for today.
