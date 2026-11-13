# 17: Reminders list roles

**What to build:** The user's Reminders lists follow a Next-Action / Someday-Maybe system
(scotthyoung.com/blog/2024/11/29/productivity-end/). Emo reads each list's role from its name and only
schedules committed work; everything else is imported and remembered but stays off the calendar.

**Blocked by:** 10

**Status:** done

| List (user's names) | Role | Scheduled |
|---|---|---|
| `NA - Personal/Home/Poli/Smolla/DEB/TA` | next action, area = suffix | yes |
| `CHECKLIST DAILY` | routine (0.25 h, low energy) | yes |
| `INBOX` | inbox: unprocessed, clarify first | no |
| `WAITING` | waiting | no |
| `PROJECTS - …` | project | no |
| `SOMEDAY - …` | someday / maybe | no |
| `GROCERIES` | shopping | no |
| `Ideas` | idea | no |

- [x] `ListAssignment.infer(fromTitle:)`: `ROLE - Area` titles, abbreviations (`NA`), spelled-out variants; unknown titles stay next actions named after themselves
- [x] `TaskItem.listRole` / `listArea`; `isPlannable` excludes non-schedulable roles (the planner's single gate)
- [x] Role and area are part of the reminder's content hash: moving a reminder from SOMEDAY to NA in Reminders.app makes it schedulable on the next sync (and existing imports get their role backfilled on the first sync)
- [x] Backlog groups tasks: To do, then Inbox / Waiting / Projects / Someday / Shopping / Ideas
- [x] Settings → Integrations shows each list's detected role and whether it's scheduled

## Comments

2026-11-13: TODAY / THIS WEEK are sections inside a list, which EventKit doesn't expose. See 22.
