# 31: Ongoing tasks with a weekly target

**What to build:** Tasks that are a practice rather than a one-off ("apply for jobs", "drop off CVs",
"study Swift"). They have a weekly target (sessions × length). Emo spreads the sessions across the
week, a done session counts toward the target, and the task itself never completes.

**Blocked by:** 30 (for `ongoing:` from notes); the Emo-side toggle writing back needs 32

**Status:** needs-triage

- Model: `TaskItem.isOngoing`, `sessionsPerWeek` (default 2), `sessionHours` (default 1). Mutually exclusive with `recurrence` (an ongoing task has none).
- Session log: a CloudKit-safe `TaskSession` (taskID, day key, hours, completedAt). "Done" on an ongoing task's block logs a session through `TaskLifecycle` instead of setting `completedAt`.
- Planner: each week, remaining = target − sessions logged this week (Mon–Sun). At most one session per day, spread out (no back-to-back days when the week allows). Each session is planned like a normal task of `sessionHours`, under the energy budget. A skip moves that session to another day this week; it isn't lost unless the week runs out.
- Marking it: either `ongoing:` in the reminder notes (30), or the "Ongoing" toggle in Emo's task editor. For reminder-backed tasks the toggle writes the `ongoing:` line back (32), so the notes stay the source of truth. Tasks created in Emo store it locally.
- Completing the reminder in Reminders.app means "stop for good": the task completes and the session history stays.
- UI: backlog row `↻ 2 of 3 this week · 1h`; editor shows sessions/week and session length when Ongoing is on.
- Import: ongoing reminders are sized from the notes, so they don't need review.
- [ ] Model + session log
- [ ] Planner targets and spreading; tests for target met, skip/reflow, week rollover, energy budget
- [ ] Lifecycle: done logs a session; upstream completion ends the task
- [ ] Editor toggle + backlog row
