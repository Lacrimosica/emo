# 32: Write context back to Reminders notes

**What to build:** Emo can update the keyed lines (30) in a reminder's notes in Reminders.app, so the
context stays with the reminder on every device.

**Blocked by:** 30

**Status:** ready-for-agent

- `AppleRemindersWriter.updateNotes(externalID:, fields:)`: fetches the reminder fresh, merges via `ReminderNotes.merging` (free text untouched), saves with `EKEventStore.save(_:commit:)`.
- Only keyed lines are ever written. Title, due date, list and completion stay owned by Reminders.app (no other write-back).
- No echo: after writing, update the `ExternalLink.contentHash` so the next sync doesn't count it as an upstream edit.
- Conflicts: if the notes changed since the last sync, merge onto the latest notes rather than overwriting.
- Requires full Reminders access (already requested in 10). If the write fails, Emo keeps the fields locally and retries on the next sync.
- [ ] Writer + engine-side "pending notes edits" queue (unit-tested without EventKit)
- [ ] Round-trip tests: user free text survives, repeated writes are idempotent

## Comments

2026-11-13 (triage): confirmed. Writes stay minimal: only keyed lines (30) change, a value is written only
when it differs from what's there, and an empty proposed value removes that one line and nothing else.
