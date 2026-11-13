# 30: Reminder notes syntax (import context from notes)

**What to build:** A small fixed syntax inside a reminder's notes that carries what EventKit loses
(indentation, sections, tags) and marks ongoing work. Emo imports the notes, parses the syntax, and every
AI call reads it through one shared base prompt.

**Blocked by:** 17

**Status:** needs-triage (confirm the syntax below)

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

- [ ] `ReminderNotes` in EmoKit (deep module): `parse(String) -> ReminderNotes` (keyed fields + free text) and `merging(_ fields:) -> String` (rewrites only keyed lines, keeps free text byte-for-byte). Tolerant parsing: case, extra spaces, `3/week`, `3x a week`, `x3`.
- [ ] `ExternalReminder.notes` read from `EKReminder.notes`; part of `contentHash` (editing notes in Reminders.app re-syncs)
- [ ] `TaskItem` stores the raw notes; parsed `partOf` / `context` are readable from the model (CloudKit-safe optionals)
- [ ] `EmoPrompt.base`: one shared system-prompt fragment explaining list roles, areas and this syntax. `TaskClarifier` and future sizers prepend it. Each task is rendered for the AI as `title · list role/area · part of · context · notes`
- [ ] Backlog row shows `part of` as a subtitle
- [ ] Tests: round-trip keeps free text, malformed lines are ignored, `#` lines are left as free text
