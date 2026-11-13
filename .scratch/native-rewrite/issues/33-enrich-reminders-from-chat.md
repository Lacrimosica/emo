# 33: Enrich reminders from Ask Emo

**What to build:** Talking to Emo's chat, the user can add context to existing reminders ("all the CV
stuff in NA - Personal is the job hunt, design roles in Milan; studying Swift is ongoing, 3 times a week").
Emo proposes minimal keyed-line edits (30) per reminder, the user approves them, and they're written back (32).

**Blocked by:** 30, 32, 12 (31 for `ongoing` edits)

**Status:** in-review

- The chat gets the base prompt (30) plus the relevant open reminders: title, list role/area and current keyed fields, filtered by list or keywords to stay small. Cloud providers only get these when selected, as in 21.
- Structured reply: `edits: [{ reminderID, set: { ongoing?, part of?, context? } }]` plus an optional single question. Values must follow the syntax and stay short (`context` ≤ ~80 chars, no restating the title).
- Review sheet: before → after per reminder, with per-row approve. Nothing is written without approval.
- Entry points: an "Add context" mode in Ask Emo, and "Clarify with Emo" on a vague backlog row (short title, INBOX role, no context yet), which opens the chat scoped to that reminder.
- [x] Prompt + structured output schema (Claude, Ollama, on-device)
- [x] Clamp/validate proposed values through `ReminderNotes` before showing them
- [x] Review sheet → writer

## Comments

2026-11-13 (triage): confirmed by the user ("talking with the agent in Emo it would go and enrich and modify
context in the reminders section, albeit minimally and according to a specific syntax written to a system prompt").
- The chat's instructions are `EmoPrompt.base` (30) plus the edit rules: touch as few reminders and keys as
  possible, never restate the title, never rewrite free text, prefer no edit over a guess, and ask one question
  when unsure.
- The edit schema includes `when` (22).
- Approval stays mandatory per reminder (review sheet).

2026-11-13 (implementation):
- `ReminderEnrichment` (EmoKit/AI): the instructions are `EmoPrompt.base`, then `ReminderEnrichment.rules` (as few reminders and keys as possible, never restate the title, never rewrite free text, prefer no edit over a guess, one question when unsure), then the reminders numbered `[n] title · role/area · part of · context · …`. `EnrichmentReply` is the structured output (`@Generable` for on-device, a JSON schema for Claude and Ollama): `question` plus `edits: [{reminder, partOf, context, when}]`, where null means leave it, "" means remove, and `when` is today/week. Edits are validated before review: single line, no `#`, `context` ≤ 80 and `part of` ≤ 40 characters (cut at a word), a value that just restates the title is dropped, `when` must be today/week, unknown ids are ignored, edits to the same reminder merge, and anything that wouldn't change the notes is dropped (`ReminderNotesWriteBack.minimal`).
- Only open tasks linked to Apple Reminders are candidates. They're filtered by word overlap with what the user said (title, area, part of, role), capped at 30 to fit the on-device model, falling back to the first 30. Only the selected provider ever sees them.
- `ContextChatSheet` (Shared): the chat, then a review card with before → after per key and an approve toggle per reminder (all on by default). "Update N Reminders" goes through `RemindersSyncService.writeNotes` (32). Nothing is written without approval. If Reminders isn't connected, edits are kept in Emo and written later.
- Entry points: Ask Emo is now a menu (New Task, the default; Add Context to Reminders) on Mac and iPhone. "Clarify with Emo" opens the chat scoped to one task: in the row's right-click menu on the Mac, and in the long-press menu plus a swipe action for vague tasks on iPhone. `TaskItem.looksVague` (imported, no `context:`, and an inbox role or a title of two words or fewer) shows a "Needs context" hint in the row.
- `ongoing` edits were added with 31: the model's value is normalised to an explicit target ("3 times a week" becomes `3x/week 1h`, and a bare yes gets the defaults), and "" stops it.

Verified: 181 EmoKit tests pass (8 new: validated minimal proposals per reminder and nothing written before approval, instructions = base + rules + numbered list, cleaning invalid values, restating the title, empty removes, unknown ids, relevance filter, candidates are only linked tasks, vague detection). Both apps build. Added an opt-in live test (`EMO_LIVE_AI=1`). The on-device model wasn't available to the test runner here, so no real model has run this flow yet. Please try Add Context with your provider.
