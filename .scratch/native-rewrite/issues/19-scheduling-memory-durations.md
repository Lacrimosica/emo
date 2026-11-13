# 19: Scheduling memory: estimate vs. actual

**What to build:** Emo learns how far off estimates are and corrects future ones
(for example "admin in NA - Poli takes about 1.4× the estimate").

**Blocked by:** 18

**Status:** needs-triage

- Signals already in the engine: completion time vs. planned blocks, skips (`skippedDayKey`), reschedules and overflow (tasks that keep spilling into the next day).
- Open question: there's no explicit time tracking. Do we approximate "actual" as the task-block time used up to completion, or add a lightweight "took longer / shorter" prompt on completion?
- [ ] Per area/category correction factor, bounded and decaying with age
- [ ] Planner uses corrected estimates; the task's own estimate field is untouched
