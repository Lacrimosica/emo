# 15: Write-back to Calendar.app

**What to build:** Emo's scheduled task blocks (and optionally transit) appear in a dedicated "Emo" calendar in Calendar.app and stay in sync as Emo replans. The engine produces outbound changes; the Apple Calendar adapter applies them. Emo's own written events are never re-imported as fixed events.

**Blocked by:** 09 (Integration seam + Apple Calendar inbound), 05 (Task lifecycle reshapes the day)

**Status:** ready-for-agent

- [ ] Opt-in toggle in Settings → Integrations; creates the "Emo" calendar on first enable
- [ ] Replanning updates, moves and deletes the corresponding Calendar.app events
- [ ] Emo-written events are excluded from inbound import (no feedback loop)
- [ ] Disabling write-back offers to remove the Emo calendar's events
- [ ] Engine's outbound change generation is unit-tested
