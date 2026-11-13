# 10: Apple Reminders inbound

**What to build:** The user grants Reminders access and selects lists. Open reminders become backlog tasks (no duplicates on re-sync), with due dates mapped to deadlines. Completing a reminder in Reminders.app completes the linked task in Emo; deleting it removes or flags the task.

**Blocked by:** 09 (Integration seam + Apple Calendar inbound)

**Status:** ready-for-agent

- [ ] EventKit Reminders adapter built on the same integration seam (change sets → engine)
- [ ] Settings → Integrations lists Reminders lists with toggles
- [ ] Imported tasks get sensible defaults for fields reminders lack (estimate, energy cost, category) and are marked as needing review
- [ ] Re-sync is idempotent (linked by external id)
- [ ] Completion and deletion in Reminders.app propagate into Emo live
- [ ] Unit tests with a fake adapter
