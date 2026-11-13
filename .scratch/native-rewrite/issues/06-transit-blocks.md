# 06: Transit blocks

**What to build:** Tasks marked as requiring transit get a transit block of the configured duration placed immediately before their first scheduled block. The user can also add a standalone transit block manually on the timeline.

**Blocked by:** 04 (Auto-scheduler)

**Status:** ready-for-agent

- [ ] Scheduler reserves transit time before a transit-requiring task and only places the task where transit + minimum chunk fits
- [ ] Transit blocks render distinctly and are labelled with the task they lead to
- [ ] User can add a standalone transit block with a start time, duration and note
- [ ] Removing or rescheduling the task removes/moves its auto transit block
- [ ] Unit tests cover transit placement
