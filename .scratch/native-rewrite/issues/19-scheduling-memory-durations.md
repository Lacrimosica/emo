# 19: Scheduling memory: estimate vs. actual

**What to build:** Emo learns how far off estimates are and corrects future ones
(for example "admin in NA - Poli takes about 1.4× the estimate").

**Blocked by:** 18

**Status:** in-review

- Signals already in the engine: completion time vs. planned blocks, skips (`skippedDayKey`), reschedules and overflow (tasks that keep spilling into the next day).
- Open question: there's no explicit time tracking. Do we approximate "actual" as the task-block time used up to completion, or add a lightweight "took longer / shorter" prompt on completion?
- [x] Per area/category correction factor, bounded and decaying with age
- [x] Planner uses corrected estimates; the task's own estimate field is untouched

## Comments

2026-11-16: Implemented with the no-new-UI option for the open question: "actual" is the task-block time
that had run when the user ticked the task done in Emo (completions synced from Reminders are ignored).
- `DurationObservation` + `DurationMemory`, grouped like ticket 20 (list area, else category). A factor needs
  3 completions; recency-weighted (half-life 45 days); bounded 0.5×–2×; rounded to 0.05; ignored within ±10%.
  Single ratios outside 0.2×–3× are dropped as noise; ongoing tasks are skipped.
- `DayPlanning` reserves `estimate × factor` (rounded to 5 min); `TaskItem.estimatedHours` is untouched.
- Settings › Planning › What Emo has learned lists the factors, with "Forget Estimate Corrections…".
- Known limit: the planner stops adding blocks once the reserved time is used, so this mostly learns that
  tasks finish early; overruns only show when blocks are stretched by hand. A "took longer / shorter"
  prompt on completion would fix that if it turns out to matter.
