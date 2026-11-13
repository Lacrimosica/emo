# 31: Ongoing tasks with a weekly target

**What to build:** Tasks that are a practice rather than a one-off ("apply for jobs", "drop off CVs",
"study Swift"). They have a weekly target (sessions × length). Emo spreads the sessions across the
week, a done session counts toward the target, and the task itself never completes.

**Blocked by:** 30 (for `ongoing:` from notes); the Emo-side toggle writing back needs 32

**Status:** in-review

- Model: `TaskItem.isOngoing`, `sessionsPerWeek` (default 2), `sessionHours` (default 1). Mutually exclusive with `recurrence` (an ongoing task has none).
- Session log: a CloudKit-safe `TaskSession` (taskID, day key, hours, completedAt). "Done" on an ongoing task's block logs a session through `TaskLifecycle` instead of setting `completedAt`.
- Planner: each week, remaining = target − sessions logged this week (Mon–Sun). At most one session per day, spread out (no back-to-back days when the week allows). Each session is planned like a normal task of `sessionHours`, under the energy budget. A skip moves that session to another day this week; it isn't lost unless the week runs out.
- Marking it: either `ongoing:` in the reminder notes (30), or the "Ongoing" toggle in Emo's task editor. For reminder-backed tasks the toggle writes the `ongoing:` line back (32), so the notes stay the source of truth. Tasks created in Emo store it locally.
- Completing the reminder in Reminders.app means "stop for good": the task completes and the session history stays.
- UI: backlog row `↻ 2 of 3 this week · 1h`; editor shows sessions/week and session length when Ongoing is on.
- Import: ongoing reminders are sized from the notes, so they don't need review.
- [x] Model + session log
- [x] Planner targets and spreading; tests for target met, skip/reflow, week rollover, energy budget
- [x] Lifecycle: done logs a session; upstream completion ends the task
- [x] Editor toggle + backlog row

## Comments

2026-11-13: Built from the spec as written; the user asked to finish all tickets.
- Model: `TaskItem.isOngoing`, `sessionsPerWeek` (default 2), `sessionHours` (default 1). Turning it on clears the recurrence and sets the estimate to one session. `TaskSession` (taskID, dayKey, hours, completedAt) is in the store schema. `TaskDraft` carries the ongoing fields (`applyOngoing`).
- Notes: `TaskItem.applyNotes(seenOn:)` maps `ongoing:` (and `when:`) onto the model on import, on every sync (assigning only what differs), and on write-back. Notes are the source of truth for tasks from Reminders, so removing the line turns it off. Ongoing imports don't need review.
- Planner: `OngoingSchedule.timeDue` (weeks run Monday to Sunday). A session counts once it's done (`TaskSession`) or planned (a staying block). At most one per day. The day after a session is skipped unless the days left in the week are no more than the sessions left. The session is planned like a normal task of `sessionHours` within the energy budget. When the sessions left fill every remaining day, the week's end works as a deadline. Skipping a day makes the session reflow to a later day that week. DayPlanning recomputes ongoing tasks for the second day, after the first day's blocks are written.
- Lifecycle: `TaskLifecycle.logSession` logs the block time done (or one session's length), clears the rest of that day's blocks and re-plans. "Complete" on an ongoing block or in the backlog logs a session ("Done for Today"). "Stop Ongoing Task" or completing the reminder ends it for good, and the session history stays.
- UI: an Ongoing toggle in the editor with sessions a week and session length (it hides the estimate and Repeats). For tasks from Reminders, the toggle writes `ongoing: <n>x/week <len>` back (32). Backlog rows show "↻ 2 of 3 this week · 1h" (green once met). The Mac editor's fixed min width is Mac-only now (it was wider than a phone).
- 33 now also proposes `ongoing` edits, always with an explicit target.

Verified: 193 EmoKit tests pass (10 new for ongoing: planned at one session's length, spreading, back-to-back when the week runs out, target met, week rollover, logging keeps the task open, skip reflows, energy budget, read from notes without review, completing the reminder ends it) and both apps build. Not tried by hand in the apps.
