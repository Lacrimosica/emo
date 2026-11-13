# 29: iPhone Ask Emo chat and voice

**What to build:** The Ask Emo chat on iPhone: describe a task (typed or dictated), answer at most one question at a time, then review the proposal and add it. AI provider settings (Apple on-device, Ollama, Claude with model picker; keys in the iOS Keychain) are available on the phone.

**Blocked by:** 25 (iPhone walking skeleton)

**Status:** ready-for-agent

- [ ] Chat sheet with proposal review, reusing `TaskClarifier` and the providers
- [ ] Dictation with microphone and speech permissions (on-device recognition where supported)
- [ ] AI settings screen with provider choice, model picker and Test Connection
- [ ] Ollama note: a local Mac Ollama is only reachable from the phone over the LAN (host set to the Mac's address); document it in the screen's footer
