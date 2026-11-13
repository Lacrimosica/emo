# 30: Reminder notes syntax (import context from notes)

**What to build:** A small fixed syntax inside a reminder's notes that carries what EventKit loses
(indentation, sections, tags) and marks ongoing work. Emo imports the notes, parses the syntax, and every
AI call reads it through one shared base prompt.

**Blocked by:** 17

**Status:** in-review

## Why notes

EventKit exposes a reminder's title, notes, list, due date, priority and recurrence. It does **not**
expose subtasks/indentation, sections or tags. So "Send CV" indented under "Job hunt" arrives as a bare
"Send CV". Notes are the only free field Emo can both read and write.

Don't use `#`: Reminders turns `#word` (in the title or notes) into a tag chip, and EventKit never sees tags.

## Syntax (proposed)

One `key: value` per line, at the top of the notes. Lowercase keys. Anything else in the notes is the
user's own text: Emo passes it to the AI unchanged and never rewrites it.

```
ongoing: 3x/week 1h
part of: Job hunt
context: product design roles, Milan; use CV v3
```

| Key | Meaning | Value |
|---|---|---|
| `ongoing` | doing it doesn't finish it (see 31) | optional `<n>x/week` and session length (`45m`, `1h`, `1.5h`); bare `ongoing` = defaults |
| `part of` | the parent/section the reminder sits under | short name |
| `context` | what the AI needs to size or understand it | one short line |
| `when` | the user's TODAY / THIS WEEK goal (see 22) | `today` or `week` |

Unknown keys are kept as-is and ignored, so new keys (e.g. `when: today` for 22) can be added later.

## Tasks

- [x] `ReminderNotes` in EmoKit (deep module): `parse(String) -> ReminderNotes` (keyed fields + free text) and `merging(_ fields:) -> String` (rewrites only keyed lines, keeps free text byte-for-byte). Tolerant parsing: case, extra spaces, `3/week`, `3x a week`, `x3`.
- [x] `ExternalReminder.notes` read from `EKReminder.notes`; part of `contentHash` (editing notes in Reminders.app re-syncs)
- [x] `TaskItem` stores the raw notes; parsed `partOf` / `context` are readable from the model (CloudKit-safe optionals)
- [x] `EmoPrompt.base`: one shared system-prompt fragment explaining list roles, areas and this syntax. `TaskClarifier` and future sizers prepend it. Each task is rendered for the AI as `title · list role/area · part of · context · notes`
- [x] Backlog row shows `part of` as a subtitle
- [x] Tests: round-trip keeps free text, malformed lines are ignored, `#` lines are left as free text

## Comments

2026-11-13 (triage): the user confirmed the approach: Emo's agent enriches reminders minimally, following a
specific syntax written into the system prompt.
- The syntax is defined **once**: `EmoPrompt.base` in EmoKit is the single source of truth. The keys, value formats
  and the "minimal edits only" rules live there. Parser tests check that every example in the prompt parses, so the
  prompt and `ReminderNotes` can't drift apart.
- Keys for v1: `ongoing`, `part of`, `context`, `when` (22).
- Mirror the syntax in `GLOSSARY.md` (create it) for humans; the prompt stays authoritative.

2026-11-13 (implementation):
- `ReminderNotes` (EmoKit/Integrations): a keyed line is any line whose key is `ongoing`, `part of`, `context` or `when` (case, spaces and hyphens ignored). It doesn't have to be at the top, and a line that is just `ongoing` counts. If a key appears twice, the first one wins. Every other line is free text, including unknown keys, `#…` lines and "10:30". There are typed accessors for `partOf`, `context`, `when` (today/week) and `ongoing` (sessions/week and minutes, parsed tolerantly). `merging([Key: String?])` replaces a line in place, adds new keys after the keyed lines at the top, or removes a line when the value is nil. Every other line is kept byte for byte, including its own line ending. Notes written with Windows line endings (`\r\n`) are handled; in Swift `\r\n` counts as one character, so splitting on `\n` alone missed it.
- `ExternalReminder.notes` comes from `EKReminder.notes`. Notes join `contentHash` only when there are some, so reminders without notes keep their old hash and aren't all re-synced once. A notes-only edit updates the task without re-planning.
- `TaskItem.notes` (optional) stores the raw notes, with `parsedNotes`, `partOf` and `notesContext` read from it.
- `EmoPrompt.base` (lists, roles, areas, the syntax, the minimal-edit rules) and `EmoPrompt.render(task)` (`title · role/area · part of · context · when · ongoing · notes`). `TaskClarifier` puts the base prompt in front of its own instructions. The tests check that every example in the prompt parses and that every key is described.
- Both Backlog rows (Mac and iPhone) show `part of` under the task name.
- `GLOSSARY.md` added at the repo root (planning, lists, reminder-notes and integration terms).

Verified: 158 EmoKit tests pass (18 new), and both apps build. Not tried against real Reminders notes yet.
