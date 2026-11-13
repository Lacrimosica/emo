# 20: Scheduling memory: time-of-day patterns

**What to build:** Emo learns when the user actually does each kind of task (errands in the afternoon,
NA - Poli in the morning) and prefers those slots.

**Blocked by:** 18

**Status:** needs-triage

- Signals: when tasks are completed, which planned blocks get moved or pinned by hand, and which get skipped.
- `DayPlanner` today fills free spans in priority order; this adds a slot preference per area/category as a soft cost (it never overrides deadlines or the energy budget).
- [ ] Learned preference windows per area/category
- [ ] Planner places tasks inside preferred windows when free
- [ ] Settings shows what's been learned, and lets the user reset it
