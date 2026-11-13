# Emo

A personal day planner. Emo keeps one internal calendar of the user's commitments and fills the free time with tasks from their backlog, sized by how much energy they have that day.

## Planning

**Task**:
A unit of work the user wants done, with an estimate, an energy cost and a category. A task stays in the backlog until it is completed.
_Avoid_: Todo, item, reminder (a reminder is where a task can come from)

**Backlog**:
The user's open tasks, scheduled or not.
_Avoid_: Inbox, todo list

**Internal calendar**:
Emo's own calendar and the single source of truth for the user's time. Integrations only feed it; they never write to it directly.
_Avoid_: Schedule, agenda

**Fixed event**:
A commitment at a set time (a meeting, an appointment) that planning works around.
_Avoid_: Appointment, meeting, `fixed_event`

**Task block**:
A stretch of time on the internal calendar given to one task. A task may be split across several blocks.
_Avoid_: Slot, session, `schedule_block`

**Transit**:
Travel time on the calendar, either before a task that needs it or added on its own.
_Avoid_: Commute, travel block

**Pinned**:
Said of a task block the user placed or fixed themselves; re-planning never moves it.
_Avoid_: Locked

**Check-in**:
The user's mood and energy (1–5) for a day. The day's energy sets how much task work Emo plans.

**Energy budget**:
How many hours of task work Emo plans for a day at a given energy level.

**Plan Day**:
Filling a day's free time, inside the planning window, with backlog tasks.
_Avoid_: Auto-schedule

**Unschedule All**:
Removing every upcoming task block, pinned ones included, putting their tasks back to unscheduled.

**Skip**:
Leaving a task out of one day; it stays in the backlog and can land on the next.

## Lists

**List role**:
What a Reminders list is for, read from its name: next action, daily checklist, inbox, waiting, projects, someday, shopping or ideas. Only next-action and daily-checklist tasks are scheduled.

**Area**:
The part of life a list covers, after the role in its name ("NA - Home" is a next-action list for Home).

**Next action**:
Committed, actionable work, and the main kind of task that gets scheduled.
_Avoid_: NA (only in list names), todo

## Reminder notes

**Keyed line**:
A `key: value` line in a reminder's notes that carries context Reminders can't show Emo (sections, indentation, goals). Every other line is the user's own text, which Emo reads but never rewrites. The AI's base prompt is the authoritative definition of the keys.

**Ongoing** (`ongoing: 3x/week 1h`):
Work that doing doesn't finish, like a practice, optionally with a weekly target of sessions and session length. A bare `ongoing` uses defaults.
_Avoid_: Habit, recurring (recurring tasks finish and come back)

**Part of** (`part of: Job hunt`):
The parent or section a task sits under.
_Avoid_: Parent, project, tag

**Context** (`context: design roles, Milan`):
One short line the planner needs to size or understand a task.

**When** (`when: today`, `when: week`):
The user's goal for a task: done today, or done this week.
_Avoid_: Priority, due (a due date is a deadline, not a goal)

## Integrations

**Integration**:
An outside app that feeds the internal calendar or backlog: Apple Calendar or Apple Reminders.
_Avoid_: Sync, connector

**Linked event**:
A fixed event that comes from an integration and can only be changed there.

**Write-back**:
Emo showing its planned task and transit blocks in an "Emo" calendar in the Calendar app. Emo never imports that calendar.
_Avoid_: Export, sync
