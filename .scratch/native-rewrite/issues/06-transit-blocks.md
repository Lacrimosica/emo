# 06: Transit blocks

**What to build:** Tasks marked as requiring transit get a transit block of the configured duration placed immediately before their first scheduled block. The user can also add a standalone transit block manually on the timeline.

**Blocked by:** 04 (Auto-scheduler)

**Status:** done

- [x] Scheduler reserves transit time before a transit-requiring task and only places the task where transit + minimum chunk fits
- [x] Transit blocks render distinctly and are labelled with the task they lead to
- [x] User can add a standalone transit block with a start time, duration and note
- [x] Removing or rescheduling the task removes/moves its auto transit block
- [x] Unit tests cover transit placement

## Comments

2026-11-13: Transit is placed once per task per day, before its first planned block. It takes calendar time but not energy budget (as in the legacy engine). Auto transit carries the task's ID, so it's replaced, removed and renamed together with the task's blocks, and moving it by hand pins it. Manual transit (Today › New Event menu › Transit…) has no task and is never touched by planning. The task editor gains "Needs travel" plus travel time (5–480 min). Pinned blocks don't get automatic transit. 6 new tests.
