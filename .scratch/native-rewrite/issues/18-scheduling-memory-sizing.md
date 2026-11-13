# 18: Scheduling memory: sizing learned from the user's edits

**What to build:** Emo remembers how the user sizes tasks, so the next similar task arrives already sized
instead of with the flat 0.5 h / medium defaults.

**Blocked by:** 17

**Status:** in-review

- A `SchedulingMemory` module in EmoKit (deep module: `record(_ observation)` in, `suggest(for: title, area:, role:)` out), backed by a CloudKit-compatible SwiftData model.
- Observation: whenever the user reviews an imported task (edits it so `needsReview` clears) or creates a task, record its title keywords, list area, estimate, energy cost and category.
- Suggestion: on import, match by normalized keywords + area (e.g. "call", "dentist", area "Home") and use the learned sizing; fall back to defaults. Imported tasks stay marked Review, but the row says "sized from memory".
- [x] Learns from edits and from tasks created in Emo
- [x] Imports use learned sizing when there's a confident match
- [x] Tests: repeated edits converge, unrelated titles don't match, area disambiguates

## Comments

2026-11-13: Built from the spec; the user asked to finish all tickets.
- `SchedulingMemory` (EmoKit/Memory) with the `SizingObservation` model (CloudKit-safe, in the schema, capped at 500, oldest dropped). `record(task)` stores the title keywords (lowercased words of three letters or more, minus filler, plural "s" dropped), area, role, estimate, energy and category. Ongoing tasks are skipped (they're sized per session).
- `suggest(for:area:role:)`: a past task counts as similar when it shares at least half of the new title's keywords. The same area adds 0.25 and a different area subtracts 0.25. Only the closest matches are used, recency-weighted (half-life of 2 newer observations): the estimate is the weighted average rounded to 15 minutes, and energy and category are weighted votes. Nil when nothing matches.
- Recording happens on every save in the task editor (creating a task, or reviewing or editing one, which is what clears Review). Imports and upstream edits never record.
- Imports (`ReminderReconciler`, non-routine lists) use a suggestion when there is one. The task stays Review and is flagged `sizedFromMemory` ("Review · sized from memory" in the row). The flag clears on the user's next edit and survives upstream edits.

Verified: 200 EmoKit tests pass (7 new: repeated edits converge, unrelated titles don't match, area disambiguates, recency weighs more, keyword normalisation, imports use memory and say so, the memory is capped). Both apps build.
