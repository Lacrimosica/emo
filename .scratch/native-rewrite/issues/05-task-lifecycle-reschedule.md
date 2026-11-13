# 05: Task lifecycle reshapes the day

**What to build:** Completing, skipping, editing or deleting a task reschedules the rest of the day automatically. The user can also pin a task to a specific time (which locks it so replanning respects it) and delete an individual block.

**Blocked by:** 04 (Auto-scheduler)

**Status:** ready-for-agent

- [ ] Mark a task complete from Today or Backlog; its future blocks are removed and remaining time is replanned
- [ ] Skip a task for today; it returns to the backlog and the day replans without it
- [ ] Editing a task's estimate, energy cost or deadline replans affected days
- [ ] Deleting a task removes its blocks and replans
- [ ] Pin a task to a chosen start/end time; pinned blocks are locked and survive replanning
- [ ] Delete a single block without deleting the task
- [ ] Recurring tasks (daily/weekly) create their next occurrence on completion
