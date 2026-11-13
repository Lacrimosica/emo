# 16: Retire the legacy web app

**What to build:** Once the native app reaches feature parity, delete the SvelteKit client, the Hono/Cloudflare server, the D1 migrations and the npm workspace setup. The README describes the native app; the migration section in the domain docs shrinks accordingly.

**Blocked by:** 05, 06, 07, 08, 10, 12, 13

**Status:** ready-for-human

Deleting the deployed Cloudflare Worker, Pages project and D1 database is a human decision; the agent removes only the code.

- [ ] Parity checklist confirmed against the legacy feature list (task input, AI clarification, voice, check-in, scheduling, weekly view, backlog, auto-reschedule, transit, settings)
- [ ] Legacy client, server, migrations, root package.json/lockfile and `.env.example` removed
- [ ] README rewritten for the native app (requirements, building with Xcode, permissions, AI provider setup)
- [ ] Migration context in the domain docs updated
