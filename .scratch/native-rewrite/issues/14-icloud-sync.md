# 14: iCloud sync

**What to build:** Emo's data (tasks, internal calendar, check-ins, settings, external links) syncs via CloudKit, so a second Mac or a reinstall shows the same state.

**Blocked by:** 05 (Task lifecycle reshapes the day)

**Status:** ready-for-human

Needs the user's paid Apple Developer account: enabling the iCloud capability, creating the CloudKit container, and signing with the team happen in Xcode / the developer portal.

- [ ] iCloud + CloudKit capability enabled with a named container
- [ ] Store configured for CloudKit mirroring; no model migration required (validates ticket 01's constraints)
- [ ] Data created on one Mac appears on another signed into the same iCloud account
- [ ] Integration-imported data does not duplicate when two Macs both run the same integration (external links dedupe)
- [ ] App works fully offline and when iCloud is signed out
