# 27: iPhone Week view and Settings

**What to build:** A week overview fitted to a phone screen (e.g. a scrollable 7-day agenda or a compact 3-day/7-day grid) that opens a day in Today, plus an in-app Settings screen for planning settings (day window, shortest block, energy budget).

**Blocked by:** 26 (iPhone Today)

**Status:** in-review

- [x] Week view readable on iPhone widths; tapping a day or block opens it in Today
- [x] Settings screen edits `PlannerSettings` with the same validation as the Mac
- [ ] Dynamic Type and VoiceOver labels checked

## Comments

2026-11-13: The iPhone app now has Week and Settings tabs. Week (`EmoPhone/PhoneWeekView.swift`) is a 7-day agenda, one section per day. Each day header shows the date, a Today badge, the hours of task blocks planned and the check-in energy. Events are listed in time order, all-day ones first, and past ones are dimmed. Tapping a day header or an event opens that day in Today. The toolbar has previous/next week buttons and "This Week", and the list opens scrolled to today. Settings (`PhoneSettingsView.swift`) is a list with Planning for now. The planning form moved from the Mac Settings to `Shared/Settings/PlanningSettingsView.swift`, so both apps use the same form and the same `PlannerSettingsStore` checks. AI and Integrations join the list in 28 and 29.

Verified: both apps build and the EmoKit tests pass. Screenshots checked: Week at the accessibility-large text size (it scrolls, and long titles wrap) and Settings. VoiceOver labels are written for the day headers (date, today, planned hours, energy) and the rows (title, time, pinned, past), but nobody has listened to them with VoiceOver yet. The week title cuts off at very large text sizes.

2026-11-16: Accessibility pass (code). Timeline blocks read as one VoiceOver element, which hid the buttons drawn
on them; they're now VoiceOver actions (complete / skip / pin / remove, or delete; move and lengthen/shorten by
15 min), offered only on editable blocks (read-only Calendar events no longer offer "move"). The week title
shortens to "16–22 Nov" at accessibility text sizes, and the Today date header may wrap to two lines there.
Box left open until someone actually listens with VoiceOver.
