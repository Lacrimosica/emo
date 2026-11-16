# 21: AI memory notes and context for vague tasks

**What to build:** A plain-text memory the AI assistant reads (and the user can see and edit) when it sizes
or clarifies tasks. Vague items ("that thing from the call", most INBOX items) get context from it, or the
assistant asks once and stores the answer.

**Blocked by:** 18, 12

**Status:** in-review (pending manual check, see Comments)

- Memory notes: short facts like "Poli = university; DEB tasks are usually calls", "groceries happen Saturday morning". Written by the assistant after clarifying, editable in Settings.
- `TaskClarifier` (and a new import-time sizer) get the relevant notes plus learned sizing (18) in their instructions.
- Vague-task detection on import: short or pronoun-heavy titles, or the INBOX role. Emo offers "Clarify with Emo" in the backlog row and saves what it learns as a note.
- Privacy: notes stay local (iCloud with 14). Only the relevant ones go to a cloud provider, and only when that provider is selected.
- [x] Notes model + Settings editor
- [x] Clarifier and sizer read the notes (clarifier and enrichment; import-time sizer deferred)
- [x] Clarifying a vague task writes a note

## Comments

2026-11-13: Per-reminder context now lives in the reminder's own notes (30) and is written from the chat (33).
This ticket keeps the cross-cutting facts ("Poli = university", "groceries on Saturday morning").

2026-11-16: Done on the development side.
- `MemoryNote` model + `AIMemory` (add/update/delete, dedupe, relevance filter: all notes while there are 8 or fewer, otherwise word overlap, max 8). Added to the SwiftData schema.
- `TaskClarifier` and `ReminderEnrichment` take the relevant notes in their instructions. Enrichment replies with an optional `remember` fact; one already known isn't suggested again.
- Add Context / Clarify with Emo show a "Remember for next time" row (on by default), saved with the reminder updates or alone.
- Settings › AI › Memory lists the notes, editable on Mac and iPhone.
- Deferred: the import-time sizer, and having Ask Emo (`TaskClarifier`) suggest notes too. Both are prompting work, left until the ML pass.
- Manual check: tell Clarify with Emo something general ("DEB stuff is always a call"), keep the note, then check it shows in Settings and in later chats. Not yet checked against a live model.
