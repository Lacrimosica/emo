# 12: Ollama and Claude providers

**What to build:** The user picks the AI provider in Settings: Apple on-device, Ollama (local or Ollama Cloud host + key) or Claude (Anthropic API key, model selectable). Keys are stored in the macOS Keychain. The task chat behaves the same whichever provider is chosen.

**Blocked by:** 11 (AI provider seam), 08 (Scheduling settings)

**Status:** done

- [x] Ollama provider: configurable host URL and optional API key; model name configurable
- [x] Claude provider via the Anthropic Messages API; defaults to a current Claude model; model configurable
- [x] API keys stored and read via Keychain, never in the database or UserDefaults
- [x] Settings → AI section to choose provider, enter credentials, and test the connection
- [x] Errors (bad key, offline, rate limit) surface in the chat as readable messages
- [x] Same clarification contract tests run against each provider with a stubbed transport

## Comments

2026-11-13:
- **Claude:** raw HTTP to the Messages API (there's no official Swift SDK). It sends `claude-opus-5-5` with `anthropic-version: 2026-10-21`. Structured output goes through `output_config.format` (json_schema), because forced `tool_choice` returns a 400 on current models. Effort is `low`, there's no `temperature` (a 400 on 2026-10-21), and server-side refusal fallback is on (`fallbacks: "default"`, beta `server-side-fallback-2026-07-01`). Text blocks are read and thinking blocks ignored; `refusal` and `max_tokens` stops become errors. 401/402/403/404/429/5xx/529 and offline map to readable messages.
- **Ollama:** `/api/chat` with `format` (JSON Schema) and `think: false`. Thinking took about 85 s on gemma4:12b versus about 2 s without it; if a model rejects `think`, the request is retried once without it. `num_predict` is capped at 1024.
- **Bug found live:** re-encoding the schema through JSONSerialization reordered its keys (task before question), and gemma4 then generated whitespace until timeout. The schema is now inserted verbatim, with a regression test.
- **Keys and settings:** keys are stored in the Keychain via `KeychainStore`. Provider, host and model are per-Mac UserDefaults (a local Ollama host is machine-specific). Settings › AI has the provider picker, credentials and Test Connection. The sandbox gained `network.client`.

Verified:
- 14 provider unit tests with a stubbed transport.
- A live local Ollama round trip (`EMO_LIVE_AI=1 EMO_OLLAMA_MODEL=gemma4:12b swift test --filter localOllama`).
- In the sandboxed app, Test Connection against Ollama returned "Working. Proposed “Buy milk”.", and a Keychain save and delete worked through the UI.

Claude was not called live (no key used).

2026-11-13 (follow-up): The Claude default is now `claude-haiku-5-5` (the user asked for a low-cost model). The server-side refusal fallback is sent only for models that accept it (Opus 5.x, Sonnet 5.5, Fable 5.x); Haiku 5.5 has none. Settings › AI model fields are now dropdowns, filled from the Anthropic Models API (`GET /v1/models`, paginated, no tokens used) and Ollama `/api/tags`, with a refresh button and a text-field fallback when listing fails. Verified in the app: the dropdown listed 15 models from the user's account with Haiku 5.5 selected. The user's own Test Connection on Claude succeeded.
