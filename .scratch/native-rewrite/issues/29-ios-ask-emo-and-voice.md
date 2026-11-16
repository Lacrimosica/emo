# 29: iPhone Ask Emo chat and voice

**What to build:** The Ask Emo chat on iPhone: describe a task (typed or dictated), answer at most one question at a time, then review the proposal and add it. AI provider settings (Apple on-device, Ollama, Claude with model picker; keys in the iOS Keychain) are available on the phone.

**Blocked by:** 25 (iPhone walking skeleton)

**Status:** in-review

- [x] Chat sheet with proposal review, reusing `TaskClarifier` and the providers
- [x] Dictation with microphone and speech permissions (on-device recognition where supported)
- [x] AI settings screen with provider choice, model picker and Test Connection
- [x] Ollama note: a local Mac Ollama is only reachable from the phone over the LAN (host set to the Mac's address); document it in the screen's footer

## Comments

2026-11-13: The Backlog tab on iPhone has an Ask Emo button (sparkles) in the toolbar and in the empty state. It opens the shared `TaskChatSheet`. On iOS the proposal review (`TaskEditorSheet`) is wrapped in a NavigationStack so its Cancel/Save buttons show. Settings › AI uses the shared `AISettingsView` (provider, model picker, Test Connection). Keys go in the phone's own Keychain. The copy says iPhone, not Mac. Dictation shows an iPhone-specific permission message and releases the audio session when it stops.

Ollama from the phone: `Config/EmoPhone-Info.plist` (merged into the generated plist) sets `NSAllowsLocalNetworking`, so plain http to LAN addresses works, plus a local-network usage description. The screen's footer explains: enter the Mac's Wi-Fi address (e.g. http://192.168.1.20:11434) and start Ollama with `OLLAMA_HOST=0.0.0.0`.

Verified: both apps build (after `xcodegen`) and the EmoKit tests pass. Screenshots checked: the chat sheet on iPhone (Apple on-device provider available in the Simulator) and AI settings with Ollama and the footer. Not tested: an actual conversation and proposal, dictation (the Simulator microphone is unreliable; best on a device), and Ollama over the LAN.

2026-11-16: Ticked: dictation is in the shared `TaskChatSheet` (`DictationController`), and the iPhone target has the mic and speech usage strings. Not tried on a real device yet (install blocked, see 25).
