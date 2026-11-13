# 13: Voice input for task chat

**What to build:** The user can dictate a task description instead of typing it; the transcription lands in the chat input and flows through the normal clarification chat.

**Blocked by:** 11 (AI provider seam + Apple on-device task chat)

**Status:** ready-for-agent

- [ ] Mic button in the chat starts/stops on-device speech recognition
- [ ] Microphone and speech-recognition permission prompts with usage descriptions; graceful denied state
- [ ] Live partial transcription shown; user can edit before sending
- [ ] Works offline where on-device recognition is available
