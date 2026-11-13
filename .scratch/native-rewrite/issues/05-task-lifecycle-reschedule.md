# 05: Task lifecycle reshapes the day

**What to build:** Completing, skipping, editing or deleting a task reschedules the rest of the day automatically. The user can also pin a task to a specific time (which locks it so replanning respects it) and delete an individual block.

**Blocked by:** 04 (Auto-scheduler)

**Status:** done (pending manual UI check, see Comments)

- [x] Mark a task complete from Today or Backlog; its future blocks are removed and remaining time is replanned
- [x] Skip a task for today; it returns to the backlog and the day replans without it
- [x] Editing a task's estimate, energy cost or deadline replans affected days
- [x] Deleting a task removes its blocks and replans
- [x] Pin a task to a chosen start/end time; pinned blocks are locked and survive replanning
- [x] Delete a single block without deleting the task
- [x] Recurring tasks (daily/weekly) create their next occurrence on completion

## Comments

2026-11-13: Implemented in `TaskLifecycle` (complete / reopen / skip / update / delete / pin) on top of new `CalendarEngine` task-block operations. 15 new unit tests cover every criterion.

Decisions:
- A change re-plans only the days where the task had (or now has) future blocks. Editing an unscheduled task leaves the calendar alone.
- Completing mid-block keeps the done part as history (cut at "now"). A remnant under 5 minutes is removed.
- Skip records `skippedDayKey`. Planning leaves the task out of that day (pinned blocks included), and it can land the next day.
- A recurring task's next occurrence gets `availableFromDayKey` (the next day, or the next week), so it isn't planned again on the day it was completed. The deadline shifts by the same step.
- Pinning releases the task's other unpinned future blocks, so its time isn't double-booked.
- Moving or resizing a task block by hand pins it. The editor's Pinned toggle can override that.
- Removing a single block doesn't re-plan, because the planner would just put it back. The time returns to the backlog for the next plan.

Verified in the app: the store migrated cleanly to the new optional fields, Plan Day placed a block, and Complete Task removed it and marked the task done.

Manual check still to do (synthetic input can't drive these menus reliably):
- Backlog: checkbox completes; right-click › Edit… / Schedule at… / Delete…; double-click edits; swipe actions.
- Timeline right-click on a task block: Skip for Today, Pin Here / Unpin, Edit Task…, Remove Block. The pin icon appears when pinned.
- Block editor for a task block: Pinned toggle, Complete Task, Skip Today.
