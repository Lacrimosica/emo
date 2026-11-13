# 09: Integration seam + Apple Calendar inbound

**What to build:** The user grants Calendar access and selects which calendars (from Calendar.app: iCloud, Google, Exchange, subscribed…) Emo should read. Their events appear in Emo as linked fixed events. When something changes in Calendar.app, Emo updates live: the integration adapter only reports a change set (added / changed / removed external items); the calendar engine reconciles it against its external links, updates linked internal events, ejects colliding task blocks and replans. Disabling the integration or deselecting a calendar removes its linked events cleanly.

**Blocked by:** 04 (Auto-scheduler)

**Status:** done

- [x] Integration adapter protocol in EmoKit: adapters emit change sets and never write the internal calendar directly
- [x] External link records (provider, external id, source calendar, content hash, last seen) let the engine distinguish moved vs. deleted vs. new
- [x] EventKit-based Apple Calendar adapter with the macOS permission prompt (usage description in Info.plist) and a graceful denied state
- [x] Settings → Integrations lists available calendars with toggles
- [x] Initial import of selected calendars over a rolling window (e.g. next 14 days)
- [x] Live updates via the EventKit change notification; edits in Calendar.app reflect in Emo within seconds
- [x] Colliding task blocks are ejected and the day replans; locked/pinned tasks that collide are surfaced to the user rather than silently moved
- [x] All-day events handled (shown, but not treated as busy time unless configured)
- [x] Reconciler is unit-tested with a fake adapter (add, move, delete, re-add, calendar deselected)

## Comments

2026-11-13:
- **Seam:** adapters report a `CalendarSnapshot` (everything in the selected sources within a window). `CalendarReconciler` diffs it against `ExternalLink` records (provider, external ID, source, content hash) into adds, updates and removals, writing linked events through internal-only `CalendarEngine` methods. Linked events stay read-only to the user.
- **Repairs:** afterwards it re-plans the touched upcoming days that already have a plan (unplanned days stay unplanned), and reports pinned task blocks that now collide (shown as a warning on Today, never moved).
- **All-day events** get an `isAllDay` flag. They're excluded from busy time and shown in a strip above the Today timeline and in the Week headers.
- **`AppleCalendarSource` (EventKit):** reads all accounts on the Mac. External ID = `calendarItemExternalIdentifier` (plus the occurrence date for recurring events), stable across devices. The window is 14 days from today.
- **`CalendarSyncService`:** syncs at launch, on `EKEventStoreChanged` (debounced 1 s), on app activation, on day change, and on Sync Now. The enabled flag and selected calendars are per Mac (UserDefaults), because calendar IDs are device-specific. Turning it off or deselecting a calendar removes those linked events.
- **Platform:** the sandbox gained the `personal-information.calendars` entitlement, plus NSCalendarsFullAccessUsageDescription (and NSRemindersFullAccessUsageDescription for ticket 10).
- **Tests:** 12 reconciler tests with fake snapshots (add, idempotent re-apply, move, remove, delete then re-add, window history, source deselect, collision re-plan, unplanned days, pinned conflict, all-day, read-only). The store migration was verified on the real data.

Manual check: enable Settings › Integrations › Apple Calendar (approve the macOS prompt), confirm events appear, then edit, move and delete one in Calendar.app and watch Emo update within seconds.

2026-11-13: Verified on real data: 49 events imported from the user's calendars.
