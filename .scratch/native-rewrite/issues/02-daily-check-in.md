# 02: Daily check-in

**What to build:** On the first launch of a day (local calendar day), the app asks for mood and energy on a 1–5 scale. Today shows the recorded values and the user can change them at any time. One check-in per day; changing it updates rather than duplicates.

**Blocked by:** 01 (Walking skeleton)

**Status:** done

- [x] Check-in prompt appears automatically when no check-in exists for today's local date
- [x] Mood and energy are each 1–5; both required to submit
- [x] Today displays the current day's mood and energy and lets the user edit them
- [x] Re-submitting for the same day updates the existing record
- [x] Day boundary uses the user's local timezone, not UTC (unit-tested around midnight)
