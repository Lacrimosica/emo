# 16: Retire the legacy web app

**What to build:** Once the native app reaches feature parity, delete the SvelteKit client, the Hono/Cloudflare server, the D1 migrations and the npm workspace setup. The README describes the native app; the migration section in the domain docs shrinks accordingly.

**Blocked by:** 05, 06, 07, 08, 10, 12, 13

**Status:** done (code removed; Cloudflare resources left for the user)

Deleting the deployed Cloudflare Worker, Pages project and D1 database is a human decision; the agent removes only the code.

- [x] Parity checklist confirmed against the legacy feature list (task input, AI clarification, voice, check-in, scheduling, weekly view, backlog, auto-reschedule, transit, settings)
- [x] Legacy client, server, migrations, root package.json/lockfile and `.env.example` removed
- [x] README rewritten for the native app (requirements, building with Xcode, permissions, AI provider setup)
- [x] Migration context in the domain docs updated

## Comments

2026-11-13: Parity confirmed against the legacy feature list:

| Legacy feature | Native ticket |
|---|---|
| Free-form task input (text or voice) | 01, 13 |
| AI clarification | 11 and 12 (Apple, Ollama, Claude) |
| Daily check-in | 02 |
| Smart scheduling | 04 |
| Weekly view | 07 |
| Backlog | 01 and 05 |
| Auto-reschedule | 05 |
| Transit | 06 |
| Settings | 08 |
| Google Calendar | replaced by 09 (any account added in macOS Internet Accounts, Google included, arrives through Calendar.app) |

Removed: `client/`, `server/`, root `package.json` and lockfile, `.env.example`, and `DATABASE.md` (the D1 schema). The `.gitignore` was trimmed of Node, SvelteKit and Wrangler entries. README rewritten for the native app. The domain docs' migration section became "Codebase context". CLAUDE.md updated.

Not done (the user's decision): deleting the deployed Cloudflare Worker, Pages project, D1 database and the Google OAuth client. The code is still in git history (`git log -- client server`).
