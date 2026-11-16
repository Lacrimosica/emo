# Emo

## Agent skills

### Issue tracker

Issues are local markdown files under `.scratch/<feature>/`. See `docs/agents/issue-tracker.md`.

### Triage labels

Default five-role vocabulary, recorded as a `Status:` line in each issue file. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: root `GLOSSARY.md` + `docs/adr/`; all code is in `apple/` (the old web app is only in git history). See `docs/agents/domain.md`.

## Native app (apple/)

- `apple/project.yml` defines the Xcode project (XcodeGen). After changing it: `cd apple && xcodegen`. App sources are a synced folder, so new files under `apple/Emo/` need no regeneration.
- Domain logic, models and persistence live in the `apple/EmoKit` Swift package; SwiftUI views stay thin.
- Test the domain: `cd apple/EmoKit && swift test` (requires Xcode as the active developer dir, or prefix with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`).
- Build the app: `cd apple && xcodebuild -project Emo.xcodeproj -scheme Emo -derivedDataPath build/DerivedData -allowProvisioningUpdates build`.
- Signing: both targets use the user's free Personal Team (`DEVELOPMENT_TEAM` in `project.yml`), so macOS keeps Calendar/Reminders/mic permissions across rebuilds. Don't switch back to ad-hoc signing (`CODE_SIGN_IDENTITY "-"`): every rebuild then looks like a new app and re-prompts. Free-team limits: iPhone installs expire after 7 days, at most 3 apps per device, no iCloud/CloudKit capability.
- Swift type for a domain "task" is `TaskItem` (avoids clashing with Swift concurrency's `Task`).
