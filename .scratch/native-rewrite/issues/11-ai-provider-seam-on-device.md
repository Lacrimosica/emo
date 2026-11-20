# 11: AI provider seam + Apple on-device task chat

**What to build:** The user types a loose task description into a chat. The assistant asks at most one clarifying question at a time and, once it has name, estimated hours, energy cost and category, creates the task in the backlog. Runs on Apple's on-device Foundation Models: no API key, works offline. The chat talks to a provider-agnostic interface so other providers can be added (ticket 12).

**Blocked by:** 01 (Walking skeleton)

**Status:** done (live on-device check pending, see Comments)

- [x] LLM provider protocol in EmoKit, independent of any vendor SDK
- [x] Apple on-device provider implementation, with a clear message when the model is unavailable on this Mac
- [x] Clarification flow: one question per turn; ends with a structured task (prefer structured/guided output over parsing free text)
- [x] User confirms (and can tweak) the proposed task before it is saved
- [x] Clarification logic is tested with a fake provider

## Comments

2026-11-13: `LLMProvider` returns structured output (`StructuredOutput`: Decodable plus a JSON Schema string). `AppleOnDeviceProvider` uses Foundation Models guided generation, so the `@Generable` `ClarifierReply` (question or task) always comes back well-formed. `TaskClarifier` owns the rules: one question per turn (extra questions trimmed), and a forced proposal after 4 questions. Proposals are normalised (estimate rounded to 15 min and clamped to 0.25–24 h, unknown enums defaulted). The user reviews the proposal in the task editor before it's added. "Ask Emo" is in the Backlog toolbar (⇧⌘N; ⌥⌘N didn't register).

Verified: 9 clarifier tests with a scripted provider. In the app, the sheet opens and shows the availability banner.

Not yet verified: a real on-device round trip. On 2026-11-13 this Mac reported "model still downloading". Re-run with `EMO_LIVE_AI=1 swift test --filter LiveProvider` once Apple Intelligence finishes downloading.

2026-11-20: Re-ran `EMO_LIVE_AI=1 swift test --filter LiveProvider`. Still not verified: Apple Intelligence reports "still downloading" on this Mac, so both on-device tests fail at the availability check. The Ollama test fails because `gemma3:12b` is not pulled locally. Code unchanged; both are environment blockers.
