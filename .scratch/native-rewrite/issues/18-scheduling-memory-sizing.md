# 18: Scheduling memory: sizing learned from the user's edits

**What to build:** Emo remembers how the user sizes tasks, so the next similar task arrives already sized
instead of with the flat 0.5 h / medium defaults.

**Blocked by:** 17

**Status:** needs-triage

- A `SchedulingMemory` module in EmoKit (deep module: `record(_ observation)` in, `suggest(for: title, area:, role:)` out), backed by a CloudKit-compatible SwiftData model.
- Observation: whenever the user reviews an imported task (edits it so `needsReview` clears) or creates a task, record its title keywords, list area, estimate, energy cost and category.
- Suggestion: on import, match by normalized keywords + area (e.g. "call", "dentist", area "Home") and use the learned sizing; fall back to defaults. Imported tasks stay marked Review, but the row says "sized from memory".
- [ ] Learns from edits and from tasks created in Emo
- [ ] Imports use learned sizing when there's a confident match
- [ ] Tests: repeated edits converge, unrelated titles don't match, area disambiguates
