# 12: Ollama and Claude providers

**What to build:** The user picks the AI provider in Settings: Apple on-device, Ollama (local or Ollama Cloud host + key) or Claude (Anthropic API key, model selectable). Keys are stored in the macOS Keychain. The task chat behaves the same whichever provider is chosen.

**Blocked by:** 11 (AI provider seam), 08 (Scheduling settings)

**Status:** ready-for-agent

- [ ] Ollama provider: configurable host URL and optional API key; model name configurable
- [ ] Claude provider via the Anthropic Messages API; defaults to a current Claude model; model configurable
- [ ] API keys stored and read via Keychain, never in the database or UserDefaults
- [ ] Settings → AI section to choose provider, enter credentials, and test the connection
- [ ] Errors (bad key, offline, rate limit) surface in the chat as readable messages
- [ ] Same clarification contract tests run against each provider with a stubbed transport
