# 13: Voice input for task chat

**What to build:** The user can dictate a task description instead of typing it; the transcription lands in the chat input and flows through the normal clarification chat.

**Blocked by:** 11 (AI provider seam + Apple on-device task chat)

**Status:** done (pending manual mic check, see Comments)

- [x] Mic button in the chat starts/stops on-device speech recognition
- [x] Microphone and speech-recognition permission prompts with usage descriptions; graceful denied state
- [x] Live partial transcription shown; user can edit before sending
- [x] Works offline where on-device recognition is available

## Comments

2026-11-13: `DictationController` uses SFSpeechRecognizer with an AVAudioEngine tap. It requires on-device recognition when the Mac supports it, and shows partial results live, appended to whatever was already typed so the user can edit before sending. The mic button sits in the Ask Emo chat. It's disabled while the AI provider is unavailable (it's useful only alongside the chat), and dictation stops on Send or when the sheet closes. Added NSMicrophoneUsageDescription and NSSpeechRecognitionUsageDescription, plus the `device.audio-input` entitlement (required under sandbox and hardened runtime). Build verified, and the Info.plist and entitlements are confirmed in the signed app.

Manual check needed (real microphone): the first press shows both permission prompts, speech appears live in the message field, the stop button and Send end dictation, and denying permission shows the inline message. With the on-device Apple model still downloading, switch Settings › AI to Ollama to try it.
