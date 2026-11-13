# 04: Auto-scheduler fills Today

**What to build:** A "Plan my day" action places backlog tasks as task blocks into the free gaps of the internal calendar for the selected day. Port the legacy engine's behaviour: energy-based hour budget (energy 1→2h, 2→3.5h, 3→5h, 4→6.5h, 5→8h), minimum chunk length, priority by energy cost plus deadline urgency, tasks split across gaps, already-elapsed time skipped for today, overflow pushed to the next day. Fix the legacy timezone bug: all day boundaries are local calendar days.

**Blocked by:** 02 (Daily check-in), 03 (Internal calendar)

**Status:** done

- [x] Scheduler is a pure function in EmoKit (inputs: day, existing events, tasks, check-in, settings → outputs: proposed blocks) with no persistence or UI dependencies
- [x] Unit tests cover: gaps around fixed events, energy budget cap, minimum chunk, deadline priority, splitting a task across gaps, skipping past time for today, overflow to next day, DST and near-midnight days
- [x] Re-running the plan replaces previous auto-placed task blocks but never touches fixed or locked events
- [x] Today shows the generated blocks distinctly from fixed events
- [x] With no check-in for the day, planning prompts for one (or uses a documented default)

## Comments

2026-11-13: Implemented as `DayPlanner` (pure) + `DayPlanning` (reads the store, writes through `CalendarEngine`). "Plan Day" is ⌘R (⇧⌘P is taken by File › Page Setup).

Decisions:
- Planning a day re-plans **that day and the next** in one pass. Planning tomorrow with only today's overflow would wipe tomorrow's existing blocks for other tasks.
- Replaceable blocks are unlocked, Emo-owned task blocks that haven't started. Started and past blocks are history, and they count toward the task's remaining time and the day's budget.
- With no check-in, planning today asks for one first and resumes after it's saved. Other days (including the spill day) assume default energy 3.
- Planning from "now" starts at the next 5-minute mark.

Legacy bugs not carried over:
- UTC day boundaries.
- "Completed hours" summed every block, including future ones.
- The energy budget could be overshot by a whole task.
- Remainders below the minimum chunk were silently dropped. Now a task's final piece may be short, and a short task can use a gap below the minimum chunk.

Found while verifying in the app and fixed:
- ⌘N opened a second window (File › New Window). The app is now a single `Window` scene.
- Added View › Today ⌘1 / Backlog ⌘2.
