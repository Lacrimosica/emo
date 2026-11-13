# 28: iPhone Calendar and Reminders integrations

**What to build:** On the phone, the user can turn on Apple Calendar and Apple Reminders, choose calendars and lists (with the list roles from ticket 17), and see them sync live, using the shared sync services and the same reconcilers as the Mac. Calendar write-back (ticket 15) is available on iPhone too.

**Blocked by:** 25 (iPhone walking skeleton), 15 (Write-back), 17 (Reminders list roles)

**Status:** ready-for-agent

- [ ] Calendar/Reminders usage descriptions in the iOS Info.plist; permission flow with denied state and a link to Settings
- [ ] Integrations settings screen with calendar/list pickers
- [ ] Sync on launch, on foreground, and on `EKEventStoreChanged`
- [ ] Without iCloud, the phone and Mac each import independently: no duplicates within a device
