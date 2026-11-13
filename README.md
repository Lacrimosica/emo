# Emo

A native macOS planner that schedules your day around your fixed commitments, sized to your energy.

Dump tasks into the backlog (typed, dictated, or worked out with the AI assistant), check in with your mood and energy, and Emo fills the free time in your day, re-planning as things change.

## Features

- **Internal calendar.** Emo owns its calendar; outside calendars feed into it, and Emo plans around them.
- **Daily check-in.** Mood and energy (1–5); energy sets how much task work a day can hold.
- **Plan Day (⌘R).** Fits backlog tasks into free time by deadline urgency and energy cost, with travel time before tasks that need it, and moves overflow to the next day.
- **Task lifecycle.** Complete, skip for today, pin to a time, edit or delete; the affected days re-plan. Repeating tasks create their next occurrence.
- **Today, Week and Backlog** views (⌘1 / ⌘2 / ⌘3).
- **Ask Emo (⇧⌘N).** Describe a task loosely; the assistant asks at most one question at a time and proposes the task for you to review. Voice dictation included.
- **AI providers.** Apple on-device (Foundation Models), Ollama (local or cloud) or Claude, chosen in Settings › AI. API keys are stored in the Keychain.
- **Integrations.** Apple Calendar (every account on the Mac: iCloud, Google, Exchange…) and Apple Reminders sync live through EventKit.

## Requirements

- macOS 26 or later
- Xcode 27 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Building

```bash
cd apple
xcodegen                     # regenerate Emo.xcodeproj after changing project.yml
open Emo.xcodeproj           # build and run the "Emo" scheme
```

From the command line:

```bash
cd apple/EmoKit && swift test                       # domain tests
cd apple && xcodebuild -project Emo.xcodeproj -scheme Emo -derivedDataPath build/DerivedData build
```

If `xcode-select` still points at the Command Line Tools, prefix commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

## Permissions

Emo asks for access the first time you use each feature:

| Feature | Permission |
|---|---|
| Apple Calendar integration | Calendars (full access) |
| Apple Reminders integration | Reminders (full access) |
| Dictation in Ask Emo | Microphone and Speech Recognition |
| Ollama / Claude | Outgoing network connections (sandbox entitlement) |

Local builds are ad-hoc signed, so macOS treats each rebuild as a new app and asks for these permissions again. Signing with a (free) Personal Team avoids that (ticket 23).

## AI provider setup

- **Apple (on-device):** needs Apple Intelligence turned on. No key.
- **Ollama:** host `http://localhost:11434` for a local install (pull a model first, e.g. `ollama pull gemma4:12b`), or `https://ollama.com` with an API key.
- **Claude:** an Anthropic API key. The default model is Claude Haiku 5.5 (the cheapest); the model list comes from your account.

## Project layout

```
apple/
├── project.yml        # XcodeGen definition of the Xcode project
├── Emo/               # SwiftUI app: views, integrations wiring, settings
└── EmoKit/            # Swift package: models, calendar engine, planner, AI, integrations (tested)
docs/
├── adr/               # architecture decisions
└── agents/            # conventions for coding agents
.scratch/              # local issue tracker (specs and tickets)
```

## History

Emo started as a SvelteKit + Cloudflare Workers web app. It was rewritten as this native app and the web version was removed. The last commit containing it is the parent of the commit that deleted `client/` and `server/` (`git log -- client`).
