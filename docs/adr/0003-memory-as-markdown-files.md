# ADR-0003: Memory Stored as Markdown Files with SQLite Index

**Status:** Proposed  
**Date:** 2026-04-08

## Context

Codabrus needs persistent memory at two scopes:
- **Global** — facts about technologies, user preferences, cross-project conventions
- **Project** — goals, architectural decisions, codebase idioms for a specific project

Requirements:
- Human-readable and hand-editable (the user should be able to inspect and fix memories)
- Git-trackable (project memory lives alongside the code)
- Searchable (the agent needs to retrieve relevant memories quickly)
- Works without a running server (memories are just files)

## Decision

Store memories as **Markdown files with YAML frontmatter**, following the same format Claude Code already uses for auto-memory. An SQLite database serves as an index for efficient keyword and embedding-based search, but it is always derived from the files — the files are the source of truth.

Directory layout:
```
~/.codabrus/memory/           # global memory
  MEMORY.md                   # index (list of files with one-line descriptions)
  user_preferences.md
  tech_common_lisp.md
  ...
  .index.sqlite               # derived search index

<project>/.codabrus/memory/   # project memory
  MEMORY.md
  project_goals.md
  architecture_notes.md
  ...
  .index.sqlite
```

Each memory file:
```markdown
---
name: Common Lisp newline handling
type: tech          ; user | tech | project | decision
scope: global       ; global | project
tags: [common-lisp, strings]
created: 2026-04-08
---

In Common Lisp `"\n"` is a two-character string (backslash + n), not a newline.
Use `(format nil "~%")` or `#\Newline` to get an actual newline character.
```

Memory injection: at the start of each agent loop iteration, the context manager queries both scopes for entries relevant to the current task (keyword match against the message history), then prepends them to the system prompt.

The SQLite index stores: filename, name, tags, full-text (for FTS5), and optionally an embedding vector. Rebuilding the index from files is a one-command operation.

## Consequences

**Good:**
- Project memory can be committed to git alongside the code
- Any text editor can view and edit memories
- No dependency on an external vector database
- Index can be rebuilt from scratch if corrupted
- Familiar format (Claude Code already writes this format)

**Neutral:**
- Memory retrieval quality depends on keyword/FTS matching; embedding search requires an embedding model call
- Initial implementation uses FTS5 only; embeddings can be added later

**Risk:**
- Large memory stores could slow down the injection step
- Mitigation: limit to top-K most relevant entries; prune stale memories regularly
