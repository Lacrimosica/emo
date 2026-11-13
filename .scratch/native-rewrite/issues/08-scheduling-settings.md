# 08: Scheduling settings

**What to build:** A standard macOS Settings window where the user configures day start and end (replacing the legacy hardcoded 9:00–22:00), minimum block length, and the energy-to-hours budget. The scheduler uses these values.

**Blocked by:** 04 (Auto-scheduler)

**Status:** done

- [x] Settings window opens via the app menu / Cmd-,
- [x] Day start, day end, minimum chunk minutes and energy budget mapping are editable and persisted
- [x] Scheduler reads settings instead of constants; tests cover non-default settings
- [x] Sensible defaults match legacy behaviour (9–22, 30 min, legacy energy table)

## Comments

2026-11-13: Settings are stored in SwiftData (`PlannerPreferences`, one record, duplicates collapsed) rather than UserDefaults, so they sync with iCloud in ticket 14. `DayPlanning` and `TaskLifecycle` load the saved settings by default. Changes apply as soon as they're valid; invalid combinations show an inline error and aren't saved. Verified in the app: ⌘, opens Settings, and a stepper change persists to the store.
