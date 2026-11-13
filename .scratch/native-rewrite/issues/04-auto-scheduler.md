# 04: Auto-scheduler fills Today

**What to build:** A "Plan my day" action places backlog tasks as task blocks into the free gaps of the internal calendar for the selected day. Port the legacy engine's behaviour: energy-based hour budget (energy 1→2h, 2→3.5h, 3→5h, 4→6.5h, 5→8h), minimum chunk length, priority by energy cost plus deadline urgency, tasks split across gaps, already-elapsed time skipped for today, overflow pushed to the next day. Fix the legacy timezone bug: all day boundaries are local calendar days.

**Blocked by:** 02 (Daily check-in), 03 (Internal calendar)

**Status:** ready-for-agent

- [ ] Scheduler is a pure function in EmoKit (inputs: day, existing events, tasks, check-in, settings → outputs: proposed blocks) with no persistence or UI dependencies
- [ ] Unit tests cover: gaps around fixed events, energy budget cap, minimum chunk, deadline priority, splitting a task across gaps, skipping past time for today, overflow to next day, DST and near-midnight days
- [ ] Re-running the plan replaces previous auto-placed task blocks but never touches fixed or locked events
- [ ] Today shows the generated blocks distinctly from fixed events
- [ ] With no check-in for the day, planning prompts for one (or uses a documented default)
