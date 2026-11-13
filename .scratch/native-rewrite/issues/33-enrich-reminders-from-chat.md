# 33: Enrich reminders from Ask Emo

**What to build:** Talking to Emo's chat, the user can add context to existing reminders ("all the CV
stuff in NA - Personal is the job hunt, design roles in Milan; studying Swift is ongoing, 3 times a week").
Emo proposes minimal keyed-line edits (30) per reminder, the user approves them, and they're written back (32).

**Blocked by:** 30, 32, 12 (31 for `ongoing` edits)

**Status:** ready-for-agent

- The chat gets the base prompt (30) plus the relevant open reminders: title, list role/area and current keyed fields, filtered by list or keywords to stay small. Cloud providers only get these when selected, as in 21.
- Structured reply: `edits: [{ reminderID, set: { ongoing?, part of?, context? } }]` plus an optional single question. Values must follow the syntax and stay short (`context` ≤ ~80 chars, no restating the title).
- Review sheet: before → after per reminder, with per-row approve. Nothing is written without approval.
- Entry points: an "Add context" mode in Ask Emo, and "Clarify with Emo" on a vague backlog row (short title, INBOX role, no context yet), which opens the chat scoped to that reminder.
- [ ] Prompt + structured output schema (Claude, Ollama, on-device)
- [ ] Clamp/validate proposed values through `ReminderNotes` before showing them
- [ ] Review sheet → writer

## Comments

2026-11-13 (triage): confirmed by the user ("talking with the agent in Emo it would go and enrich and modify
context in the reminders section, albeit minimally and according to a specific syntax written to a system prompt").
- The chat's instructions are `EmoPrompt.base` (30) plus the edit rules: touch as few reminders and keys as
  possible, never restate the title, never rewrite free text, prefer no edit over a guess, and ask one question
  when unsure.
- The edit schema includes `when` (22).
- Approval stays mandatory per reminder (review sheet).
