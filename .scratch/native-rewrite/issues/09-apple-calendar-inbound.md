# 09: Integration seam + Apple Calendar inbound

**What to build:** The user grants Calendar access and selects which calendars (from Calendar.app: iCloud, Google, Exchange, subscribed…) Emo should read. Their events appear in Emo as linked fixed events. When something changes in Calendar.app, Emo updates live: the integration adapter only reports a change set (added / changed / removed external items); the calendar engine reconciles it against its external links, updates linked internal events, ejects colliding task blocks and replans. Disabling the integration or deselecting a calendar removes its linked events cleanly.

**Blocked by:** 04 (Auto-scheduler)

**Status:** ready-for-agent

- [ ] Integration adapter protocol in EmoKit: adapters emit change sets and never write the internal calendar directly
- [ ] External link records (provider, external id, source calendar, content hash, last seen) let the engine distinguish moved vs. deleted vs. new
- [ ] EventKit-based Apple Calendar adapter with the macOS permission prompt (usage description in Info.plist) and a graceful denied state
- [ ] Settings → Integrations lists available calendars with toggles
- [ ] Initial import of selected calendars over a rolling window (e.g. next 14 days)
- [ ] Live updates via the EventKit change notification; edits in Calendar.app reflect in Emo within seconds
- [ ] Colliding task blocks are ejected and the day replans; locked/pinned tasks that collide are surfaced to the user rather than silently moved
- [ ] All-day events handled (shown, but not treated as busy time unless configured)
- [ ] Reconciler is unit-tested with a fake adapter (add, move, delete, re-add, calendar deselected)
