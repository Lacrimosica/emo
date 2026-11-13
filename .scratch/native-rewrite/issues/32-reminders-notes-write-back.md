# 32: Write context back to Reminders notes

**What to build:** Emo can update the keyed lines (30) in a reminder's notes in Reminders.app, so the
context stays with the reminder on every device.

**Blocked by:** 30

**Status:** in-review

- `AppleRemindersWriter.updateNotes(externalID:, fields:)`: fetches the reminder fresh, merges via `ReminderNotes.merging` (free text untouched), saves with `EKEventStore.save(_:commit:)`.
- Only keyed lines are ever written. Title, due date, list and completion stay owned by Reminders.app (no other write-back).
- No echo: after writing, update the `ExternalLink.contentHash` so the next sync doesn't count it as an upstream edit.
- Conflicts: if the notes changed since the last sync, merge onto the latest notes rather than overwriting.
- Requires full Reminders access (already requested in 10). If the write fails, Emo keeps the fields locally and retries on the next sync.
- [x] Writer + engine-side "pending notes edits" queue (unit-tested without EventKit)
- [x] Round-trip tests: user free text survives, repeated writes are idempotent

## Comments

2026-11-13 (triage): confirmed. Writes stay minimal: only keyed lines (30) change, a value is written only
when it differs from what's there, and an empty proposed value removes that one line and nothing else.

2026-11-13 (implementation):
- `ReminderNotesWriteBack` (EmoKit): `queue(changes, for: task)` keeps only the edits that change something. A value is written only when it differs (after trimming), and an empty or nil value removes that line, only if it's there. The edits are applied to `task.notes` (and its `when` goal) at once and kept in `TaskItem.pendingNotesEditsJSON`, one queue per task, with later edits winning. `flush(using:)` writes them through `ReminderNotesWriting`. On success the task takes the saved notes and `ExternalLink.contentHash` is updated, so there's no echo on the next sync. A failure stays queued and is retried. Edits for a deleted reminder or a missing link are dropped. When an upstream edit arrives while edits are pending, the reconciler re-applies them on top.
- `AppleRemindersWriter` (EventKit) finds the reminder by external identifier (falling back to the local one) and merges onto its current notes, so a conflicting edit made since the last sync survives. It saves only if the notes changed, and never touches the title, due date, list or completion.
- `RemindersSyncService` flushes pending edits before every sync, and `writeNotes(_:for:)` queues and writes straight away (used by 33).

Verified: 173 EmoKit tests pass (9 new, with a fake Reminders: free text survives, no echo, idempotent, an empty value removes one line, merging onto upstream edits, retry after failure while syncing in between, a deleted reminder is dropped, goals apply at once, the queue survives encoding). Both apps build. Not tested: the EventKit writer against real Reminders. There's no UI that calls it until 33.
