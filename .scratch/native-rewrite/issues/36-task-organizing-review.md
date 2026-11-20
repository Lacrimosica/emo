# 36: Make task organizing understandable (functional review follow-up)

**What to build:** The fixes from the 2026-11-20 functional review of how tasks are ordered and planned:
a priority the user controls, energy matched to the day, user-defined categories with weekly targets,
visible schedule status, per-day skips, search, unsplittable tasks, and planning beyond two days.

**Blocked by:** none

**Status:** in-review (pending manual check, see Comments)

- [x] Priority (Do first / Normal / Later) drives planning and the backlog order
- [x] Energy is matched to the day's check-in instead of ranking hard tasks first
- [x] Categories are user-defined (name, colour, weekly target); built-ins keep their old keys
- [x] Backlog rows show when each task is next scheduled, or "Not scheduled"
- [x] Skips are kept per day (a second skip no longer erases the first)
- [x] Plan Day no longer waits for a check-in; it assumes medium energy and says so
- [x] Plan Day names the tasks that didn't fit
- [x] Saving or re-prioritising a task re-plans a day that is already planned
- [x] Backlog search (Mac and iPhone)
- [x] "Keep in one block" option
- [x] Plan Week (Mac ⌘R in Week, iPhone toolbar)
- [x] Week header is a single line
- [x] Store upgrade from the previous schema is tested
- [x] Ask Emo chooses from the user's categories; categories have an icon picker
- [x] New original app artwork (no photo of a real person); the iPhone app gets an icon too
- [x] The icon can be changed in Settings › App Icon (five palettes)

## Comments

2026-11-20: Built.
- Scoring (`DayPlanner.prioritized`): today goal +10000; priority +400 / 0 / −150; deadline +500 (≤1 day),
  +200 (≤3), +50 (≤7); category behind its weekly target +120; −25 per step between task energy
  (low 1, medium 3, high 5) and the day's energy. Older tasks win ties.
- `Backlog.displayOrder`: priority, then nearest deadline, then oldest. Same keys the planner leans on.
- Categories: `CategoryDefinition` model + `CategoryCatalog` (seed, add, update, delete; delete moves tasks
  to Personal; built-ins can't be deleted). Weekly time per category counts done and planned task blocks in
  the planned day's calendar week, excluding blocks being re-planned.
- `TaskItem` gains `priorityRaw`, `skippedDayKeysRaw`, `keepTogether`. The old `skippedDayKey` is still read.
- `DayPlanning.plan(from:through:)` plans day pairs across the range; the last day is planned alone
  (`plan(_:spill: false)`), so nothing lands past the range.
- Migration: `StoreMigrationTests` opens `Fixtures/store-before-categories.store`, written by commit 5c64ba5.
- Ask Emo: the schema's category is a free string; the prompt lists the user's categories (built-ins with a
  hint) and `TaskClarifier.category(named:in:)` maps the reply by name or key, else Personal.
- Artwork: `apple/Artwork/render.swift` draws an abstract poster: a desk slab on a horizon line, a microphone
  stand, a sun disc and "E mo?" ("and now?") from bars and arcs (no photos, no fonts). Palettes: lilac (main),
  night, swiss, teal, mustard. It renders `EMO.png`, the Mac icon set, the iPhone icons and the picker previews
  (`swift render.swift <out.png> <art|mac|ios|sheet> <pixels> [palette]`). Replaces the previous icon, which used
  a photo of John Cleese.
- App icon picker (Settings › App Icon, `AppIconChoice`): on iPhone a real alternate icon
  (`ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`); on the Mac the Dock icon, re-applied at launch (Finder and
  Launchpad keep lilac; changing them would mean writing into the signed bundle).
- Verified: 265 EmoKit tests pass; both apps build and bundle the new icons. Not clicked through in the app.
- Manual check: add a category with a weekly target and see its tasks planned first; set a task to Do first
  and see it move to the top and onto today; skip a task for today and tomorrow, re-plan, and see it stay off
  both; Plan Day without a check-in; Plan Week with more work than two days; search the backlog;
  a "Keep in one block" task lands only in a gap long enough for it; pick each app icon on Mac (Dock changes,
  and stays after relaunch) and on iPhone (Home Screen icon changes).
