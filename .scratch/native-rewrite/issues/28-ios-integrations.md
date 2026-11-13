# 28: iPhone Calendar and Reminders integrations

**What to build:** On the phone, the user can turn on Apple Calendar and Apple Reminders, choose calendars and lists (with the list roles from ticket 17), and see them sync live, using the shared sync services and the same reconcilers as the Mac. Calendar write-back (ticket 15) is available on iPhone too.

**Blocked by:** 25 (iPhone walking skeleton), 15 (Write-back), 17 (Reminders list roles)

**Status:** in-review

- [x] Calendar/Reminders usage descriptions in the iOS Info.plist; permission flow with denied state and a link to Settings
- [x] Integrations settings screen with calendar/list pickers
- [x] Sync on launch, on foreground, and on `EKEventStoreChanged`
- [x] Without iCloud, the phone and Mac each import independently: no duplicates within a device

## Comments

2026-11-13: `IntegrationsSettingsView` moved to `Shared/Settings/` and is now on iPhone under Settings › Calendar & Reminders. It has the calendar toggles grouped by account, the write-back section, the Reminders lists with their roles, and Sync Now with a status line. On a phone-width screen the list rows and the access-denied row stack instead of sitting side by side (`ViewThatFits`). The denied state opens Emo's page in iOS Settings, which holds its Calendars and Reminders switches. It opens System Settings › Privacy on the Mac. The wording says "the Calendar app" on iPhone and "Calendar.app" on the Mac (`PlatformNames`). `EmoPhoneApp` creates the shared `CalendarSyncService` and `RemindersSyncService`. They sync on launch (when switched on), when Calendar or Reminders changes (`EKEventStoreChanged`, debounced), when the app comes to the foreground, and at midnight. The usage descriptions were already in the iOS target. Each device keeps its own import, and the reconcilers' external links stop duplicates within a device.

Verified: both apps build. In the iPhone 18 Pro simulator, with access granted and both integrations on, the screen lists the simulator's calendars (Calendar, Birthdays) and shows "Synced 18:45". Reminders is on too (EventKit reminder fetches in the log). Not tested: the denied flow, write-back on the phone, and a real device with your accounts.
