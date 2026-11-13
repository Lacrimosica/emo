# 10: Apple Reminders inbound

**What to build:** The user grants Reminders access and selects lists. Open reminders become backlog tasks (no duplicates on re-sync), with due dates mapped to deadlines. Completing a reminder in Reminders.app completes the linked task in Emo; deleting it removes or flags the task.

**Blocked by:** 09 (Integration seam + Apple Calendar inbound)

**Status:** done (pending manual check with real reminders, see Comments)

- [x] EventKit Reminders adapter built on the same integration seam (change sets → engine)
- [x] Settings → Integrations lists Reminders lists with toggles
- [x] Imported tasks get sensible defaults for fields reminders lack (estimate, energy cost, category) and are marked as needing review
- [x] Re-sync is idempotent (linked by external id)
- [x] Completion and deletion in Reminders.app propagate into Emo live
- [x] Unit tests with a fake adapter

## Comments

2026-11-13:
- **Import:** `ReminderReconciler` mirrors open reminders into the backlog as tasks (0.5 h, medium energy, the due date as deadline; a date-only due date means end of that day), flagged `needsReview` until the user edits the task.
- **Upstream changes:** edits update only the title and due date. Completion runs `TaskLifecycle.complete`, so the plan is repaired. Deletion removes the task if it's still open. A task deleted in Emo is re-imported while its reminder is open. Turning off or deselecting a list deletes open imported tasks and keeps completed ones as history.
- **`AppleRemindersSource`:** fetches open reminders plus those completed in the last 30 days, so completions made while Emo was closed still land. `RemindersSyncService` mirrors the calendar service. 10 new tests.

Bugs found when the user enabled the integrations:
1. **Crash on launch:** the `fetchReminders` completion was written inside a `@MainActor` class, so it inherited main-actor isolation. EventKit calls it on a background queue, and the runtime isolation check trapped (EXC_BREAKPOINT in `_swift_task_checkIsolatedSwift`). The completion is now built in a `nonisolated static` function.
2. **Calendar enabled with no calendars selected:** the store didn't list calendars right after access was granted. Fixed with `store.reset()` after granting, plus auto-selecting everything on the first non-empty load until the user has chosen (the `chosen` flag).
3. **Silent idle state:** ad-hoc signing changes the app's identity on every rebuild, so macOS forgets the Calendar and Reminders grants. An enabled integration with "not determined" access now asks again (at launch and when the Integrations tab opens). The durable fix for development is signing with an Apple Development team.
