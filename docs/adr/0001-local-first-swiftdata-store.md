# 0001: Local-first SwiftData store, CloudKit-compatible from day one

**Status:** accepted (2026-11-13)

## Context

Emo is moving from a Cloudflare D1 backend to a native macOS app. Data must live on the Mac and, later, sync between the user's devices through iCloud (ticket 14). SwiftData can mirror a store to CloudKit, but only if the models follow CloudKit's rules; retrofitting those rules means a schema migration.

## Decision

- Persist with SwiftData, built in one place (`EmoStore`) inside the EmoKit package.
- Keep CloudKit **off** (`cloudKitDatabase: .none`) until ticket 14, but write every model as if it were on:
  - every stored property is optional or has a default value;
  - no `@Attribute(.unique)`; identity is a `UUID` property, deduplication is done in code;
  - relationships are optional and declare inverses;
  - enums are stored as raw `String`s behind typed computed accessors (also keeps `#Predicate` simple).
- Views read via `@Query` using descriptors exposed by EmoKit, and write only through EmoKit services (e.g. `Backlog`), never by inserting into the context directly.

## Consequences

- Enabling iCloud becomes a configuration and signing change, not a migration.
- No database-enforced uniqueness: services must check for duplicates themselves (relevant for integration imports, which dedupe through external links).
