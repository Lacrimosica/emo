# 35: Tick reminders from Emo; re-plan after a Reminders sync

**What to build:** Completing a task in Emo ticks its reminder in Reminders.app, so nothing is ticked twice.
A Reminders sync that brings in new, edited or removed reminders re-plans the day the user has already
planned, so they show up without pressing Plan Day again.

**Blocked by:** 32 (notes write-back), 34 (daily checklist)

**Status:** in-review (pending manual check, see Comments)

- [x] Completion write-back queue, flushed on save and before every sync, retried on failure
- [x] Routine checklist items: tick the reminder only when it repeats; a repeating reminder's next occurrence stays the same item
- [x] Re-plan after a sync that changed something, only on a day already planned

## Comments

2026-11-16: Built.
- `TaskItem.pendingReminderCompletion` (Bool?): `TaskLifecycle.complete` sets true for completions the user made
  (not ones from a sync); `reopen` sets false. `ReminderCompletionWriteBack.flush` writes through
  `ReminderCompletionWriting` (`AppleRemindersWriter.setCompleted`, EventKit); tasks without a linked reminder are dropped.
- The reconciler doesn't re-complete a task reopened in Emo while the reopen is still pending.
- Routine items are daily in Emo: their reminder is ticked only if it has recurrence rules (a ticked one-off would drop
  out of the list after the 30-day lookback). When a ticked repeating reminder comes back as a new reminder, the
  reconciler moves the item's link to it (same list, same title) and counts the tick for its day, instead of adding
  a duplicate. This also covers ticking it in Reminders.app.
- `RemindersSyncService` listens to `ModelContext.didSave` and flushes pending completions (debounced), so every
  completion path (backlog, calendar block) is covered.
- `DayPlanning.refreshPlannedDays`: after a sync with changes, re-plans today if it has Emo task blocks, else tomorrow
  if it does; an unplanned day waits for Plan Day.
- Verified: 237 EmoKit tests pass (8 new, fake Reminders). Both apps build. Not tested against real Reminders.
- Manual check: complete an imported task in Emo → ticked in Reminders within a second; add a reminder in a Next
  Action list after planning today → it lands on today's calendar; tick a repeating CHECKLIST DAILY reminder from Emo →
  it moves to tomorrow in Reminders and Emo still shows one item.
