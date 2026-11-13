# 22: TODAY / THIS WEEK from Reminders

**What to build:** Respect the user's TODAY and THIS WEEK subdivisions (weekly/daily goals) when planning.

**Blocked by:** 30 (notes syntax); setting it from chat needs 32, 33

**Status:** in-review

TODAY / THIS WEEK are sections inside a Reminders list, which EventKit can't see. Decided (2026-11-13):
carry them as a keyed line in the reminder's notes, using the syntax from 30.

```
when: today
when: week
```

- `when: today`: must be planned today (top priority, above deadline urgency). If it can't fit, it's flagged, not silently spilled.
- `when: week`: planned before Sunday ends; urgency rises through the week like a Sunday deadline.
- No `when:` line: normal priority.
- Only meaningful on schedulable roles (17). On Someday / Waiting etc. it's ignored (the AI should suggest moving the reminder to an NA list instead).
- Set by hand in Reminders, or by Ask Emo ("put the CV stuff on this week"), which proposes the `when:` edit for approval (33) and writes it back (32).
- Stale lines: a `when: today` left over from a past day becomes normal priority. Emo may propose clearing it in the next chat or check-in, but never rewrites it without approval.

- [x] Parse `when` in `ReminderNotes` (30); store it on `TaskItem` with the day it was seen
- [x] `DayPlanner.prioritized` honours today/week
- [ ] Add `when` to the base prompt's syntax table and to 33's edit schema
- [x] Tests: today beats deadlines, week is placed by Sunday, stale today decays

## Comments

2026-11-13: `TaskItem.whenGoalRaw` and `whenSeenDayKey` record the goal and the day it was first seen. The seen day only changes when the goal changes, so a leftover `when: today` decays. The reconciler records the goal on every sync, so notes imported under 30 pick it up too. `TaskItem.goal(on:)` returns `today` only on the seen day, and `week(endsAt:)` until the end of that week's Sunday. `PlannableTask.goal`: `today` adds +10 000 to the score (above any deadline urgency), and `week` becomes an effective deadline at Sunday's end, so urgency rises through the week. Non-schedulable roles never reach the planner. A today goal that doesn't fit on the planned day still spills over, but it is named in `Summary.unmetTodayGoals`, and Plan Day says "“X” is marked for today but didn't fit." `when` is already in `EmoPrompt.base`. Adding it to 33's edit schema happens in 33.

Verified: 164 EmoKit tests pass (6 new: today beats a deadline, an unmet today goal is reported, a stale today decays, week acts like a Sunday deadline, the seen day stays fixed, goals are read on sync), and both apps build.
