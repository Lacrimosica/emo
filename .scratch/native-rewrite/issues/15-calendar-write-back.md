# 15: Write-back to Calendar.app

**What to build:** Emo's scheduled task blocks (and optionally transit) appear in a dedicated "Emo" calendar in Calendar.app and stay in sync as Emo replans. The engine produces outbound changes; the Apple Calendar adapter applies them. Emo's own written events are never re-imported as fixed events.

**Blocked by:** 09 (Integration seam + Apple Calendar inbound), 05 (Task lifecycle reshapes the day)

**Status:** in progress (settings hookup pending, see Comments)

- [ ] Opt-in toggle in Settings → Integrations; creates the "Emo" calendar on first enable
- [ ] Replanning updates, moves and deletes the corresponding Calendar.app events
- [ ] Emo-written events are excluded from inbound import (no feedback loop)
- [ ] Disabling write-back offers to remove the Emo calendar's events
- [ ] Engine's outbound change generation is unit-tested

## Comments

2026-11-13:
- **Engine:** `CalendarWriteBack` computes create, update and delete operations from Emo's task and transit blocks over the next 14 days. It records the result in `ExternalLink`s (provider `apple-calendar-writeback`) and keeps past blocks as history. 5 tests.
- **Writer:** `AppleCalendarWriter` applies the operations to an "Emo" calendar, created on first use in the default account. An update whose event was deleted in Calendar.app becomes delete + create.
- **Sync service:** `CalendarSyncService` re-mirrors 2 s after `ModelContext.didSave`. It excludes the Emo calendar from import (from both the list and the snapshot), and handles a recreated calendar by forgetting old records. Turning the feature off asks whether to delete the Emo calendar or keep its events.
- **Pinned blocks** are mirrored like any other task block.

**Remaining:** add `WriteBackSettingsSection()` to the Integrations settings form (inside the Apple Calendar part). Deferred because another session has uncommitted edits to `IntegrationsSettingsView.swift`. Then check by hand: toggle on, Plan Day, the Emo calendar shows the blocks, a re-plan moves them, toggle off removes them.
