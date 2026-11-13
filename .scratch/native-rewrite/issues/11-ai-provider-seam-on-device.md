# 11: AI provider seam + Apple on-device task chat

**What to build:** The user types a loose task description into a chat. The assistant asks at most one clarifying question at a time and, once it has name, estimated hours, energy cost and category, creates the task in the backlog. Runs on Apple's on-device Foundation Models: no API key, works offline. The chat talks to a provider-agnostic interface so other providers can be added (ticket 12).

**Blocked by:** 01 (Walking skeleton)

**Status:** ready-for-agent

- [ ] LLM provider protocol in EmoKit, independent of any vendor SDK
- [ ] Apple on-device provider implementation, with a clear message when the model is unavailable on this Mac
- [ ] Clarification flow: one question per turn; ends with a structured task (prefer structured/guided output over parsing free text)
- [ ] User confirms (and can tweak) the proposed task before it is saved
- [ ] Clarification logic is tested with a fake provider
