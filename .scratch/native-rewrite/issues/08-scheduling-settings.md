# 08: Scheduling settings

**What to build:** A standard macOS Settings window where the user configures day start and end (replacing the legacy hardcoded 9:00–22:00), minimum block length, and the energy-to-hours budget. The scheduler uses these values.

**Blocked by:** 04 (Auto-scheduler)

**Status:** ready-for-agent

- [ ] Settings window opens via the app menu / Cmd-,
- [ ] Day start, day end, minimum chunk minutes and energy budget mapping are editable and persisted
- [ ] Scheduler reads settings instead of constants; tests cover non-default settings
- [ ] Sensible defaults match legacy behaviour (9–22, 30 min, legacy energy table)
