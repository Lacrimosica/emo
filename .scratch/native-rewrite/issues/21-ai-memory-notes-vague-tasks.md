# 21: AI memory notes and context for vague tasks

**What to build:** A plain-text memory the AI assistant reads (and the user can see and edit) when it sizes
or clarifies tasks. Vague items ("that thing from the call", most INBOX items) get context from it, or the
assistant asks once and stores the answer.

**Blocked by:** 18, 12

**Status:** needs-triage

- Memory notes: short facts like "Poli = university; DEB tasks are usually calls", "groceries happen Saturday morning". Written by the assistant after clarifying, editable in Settings.
- `TaskClarifier` (and a new import-time sizer) get the relevant notes plus learned sizing (18) in their instructions.
- Vague-task detection on import: short or pronoun-heavy titles, or the INBOX role. Emo offers "Clarify with Emo" in the backlog row and saves what it learns as a note.
- Privacy: notes stay local (iCloud with 14). Only the relevant ones go to a cloud provider, and only when that provider is selected.
- [ ] Notes model + Settings editor
- [ ] Clarifier and sizer read the notes
- [ ] Clarifying a vague task writes a note

## Comments

2026-11-13: Per-reminder context now lives in the reminder's own notes (30) and is written from the chat (33).
This ticket keeps the cross-cutting facts ("Poli = university", "groceries on Saturday morning").
