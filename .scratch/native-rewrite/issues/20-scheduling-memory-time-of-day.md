# 20: Scheduling memory: time-of-day patterns

**What to build:** Emo learns when the user actually does each kind of task (errands in the afternoon,
NA - Poli in the morning) and prefers those slots.

**Blocked by:** 18

**Status:** in-review

- Signals: when tasks are completed, which planned blocks get moved or pinned by hand, and which get skipped.
- `DayPlanner` today fills free spans in priority order; this adds a slot preference per area/category as a soft cost (it never overrides deadlines or the energy budget).
- [x] Learned preference windows per area/category
- [x] Planner places tasks inside preferred windows when free
- [x] Settings shows what's been learned, and lets the user reset it

## Comments

2026-11-13: Built from the spec; the user asked to finish all tickets.
- `TimeOfDayMemory` (EmoKit/Memory) with `TimeOfDayObservation` (CloudKit-safe, in the schema, capped at 1000). Tasks group by list area (`area:<name>`), or by category without one. The signals and their weights:
  - a completion or a logged session: +1 at that time. Completions that arrive from a Reminders sync don't count, since their time is only when Emo noticed (`learnTiming: false`).
  - a task block moved by hand: +2 at its new start, recorded in `CalendarEngine.update`, next to the existing move-pins-it rule.
  - a skip: −1 at each skipped block's start.
- Window: per group, the 4-hour stretch (on the hour) with the most net weight. It needs a net weight of at least 3, and the stretch must hold at least half the positive weight, so scattered hints learn nothing.
- Planner: `PlannableTask.preferredWindow`. `DayPlanner` now tries free time inside the window first, then the rest of the day in order (`candidates`, `take`). Priority order, deadlines and the energy budget are unchanged, and a busy window falls back to other time. Without a window, placement is exactly as before (all existing planner tests pass unchanged).
- Settings › Planning has "What Emo has learned": each learned window (area or category, then the time range), the number of task sizes remembered (18), and Forget Times… and Forget Task Sizes… with a confirmation.

Verified: 208 EmoKit tests pass (8 new: learns with enough signal, scattered hints learn nothing, skips count against a time, the planner uses the window, a busy window falls back, priority isn't overridden, moves and skips are recorded, reset). Both apps build.
