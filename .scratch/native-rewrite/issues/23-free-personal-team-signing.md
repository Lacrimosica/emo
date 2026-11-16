# 23: Sign with a free Personal Team (Mac and iPhone)

**What to build:** Builds are signed with the user's free Apple ID "Personal Team" instead of ad-hoc signing. Mac builds then keep their Calendar, Reminders, microphone and speech permissions across rebuilds, and the iPhone app (ticket 24 onwards) can be installed on the user's own device without the paid Apple Developer Program.

**Blocked by:** None (can start immediately)

**Status:** in-review (pending manual check, see Comments)

Needs the user's Personal Team ID (Xcode › Settings › Accounts, after signing in with an Apple ID). Free-provisioning limits to keep in mind: iPhone installs expire after 7 days (re-run from Xcode), at most 3 such apps per device, and no iCloud/CloudKit capability.

- [x] `DEVELOPMENT_TEAM` set in project.yml for every target; ad-hoc `CODE_SIGN_IDENTITY "-"` removed
- [ ] Rebuilding the Mac app no longer re-prompts for Calendar/Reminders access
- [x] CLAUDE.md documents the signing setup and the free-provisioning limits

## Comments

2026-11-16: Team 3R99LV35Q6 set at project level; Xcode created the Apple Development certificate on the first
`-allowProvisioningUpdates` build. The Mac app's designated requirement is now the bundle ID + certificate (was a
per-build cdhash). Left to check by hand: grant access once, rebuild, relaunch, no prompt. iPhone device install
not tried yet.
