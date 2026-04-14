# ADR-0007: Session Persistence with Markdown Files

**Status:** Accepted  
**Date:** 2026-04-15

## Context

Phase 3 requires sessions to survive Lisp image restarts. The implementation plan lists two options: SQLite (cl-dbi + cl-sqlite) or plain files (JSONL per session). We also need a format that:

1. Is human-readable and inspectable without special tools
2. Is easy to debug (open in any text editor)
3. Works well with version control if users choose to commit sessions
4. Has minimal external dependencies
5. Can be extended in Phase 3.2 when we add part-based message format

## Decision

Store each session as a **single Markdown file** with **YAML-like frontmatter** at `~/.cache/codabrus/sessions/<uuid>.md`:

```markdown
---
id: "f47ac10b-58cc-4372-a567-0e02b2c3d479"
project-dir: "/Users/art/projects/lisp/codabrus"
model: "deepseek-chat"
tokens-in: 1234
tokens-out: 567
total-cost-usd: 0.003
created-at: "2026-04-15T10:30:00+03:00"
updated-at: "2026-04-15T10:35:00+03:00"
---

## User

Fix the failing tests

## Assistant

I'll look at the test failures...
```

**Key choices:**

- **One file per session** (not a directory). Simpler for 3.1; if 3.2 needs more files, we migrate.
- **Hand-rolled frontmatter parser** instead of `cl-yaml` dependency. Our frontmatter is flat `key: value` pairs — a full YAML parser is overkill and `cl-yaml` has compatibility issues.
- **UUID v4** for session identifiers, generated via the `uuid` library.
- **`local-time`** for ISO 8601 timestamps.
- **Message body** uses `## User` / `## Assistant` markdown headings for each turn.

**Session directory:** `~/.cache/codabrus/sessions/` — follows XDG Base Directory Specification convention. Configurable via `*sessions-dir*`.

## Consequences

**Good:**
- Zero new DB dependencies (no SQLite, no cl-dbi)
- Human-readable: `cat` or any editor to inspect session state
- Easy to implement and test
- Migration path: when 3.2 adds parts, we extend the markdown body format

**Neutral:**
- Not indexed for search — `list-sessions` reads all frontmatters (fine for <100 sessions)
- Flat key-value frontmatter means no nested structures; metadata is intentionally simple

**Risk:**
- All messages in one file could get large for very long sessions
- Mitigation: future phases can split into per-turn files or switch to a directory structure
