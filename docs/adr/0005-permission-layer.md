# ADR-0005: Multi-Level Permission System for Tool Execution

**Status:** Proposed  
**Date:** 2026-04-08

## Context

Codabrus tools span a wide risk spectrum:
- `read-file` — fully safe, read-only, no side effects
- `edit-file` — modifies local files (reversible via git)
- `bash` — executes arbitrary shell commands (potentially irreversible)
- MCP tools — connect to external services (network, databases)

Running everything without asking is unsafe. Asking for every single tool call is unusable. We need a graduated, configurable permission model.

## Decision

Implement a **four-level permission cascade**, evaluated top-down; the first matching rule wins:

```
Level 1: Project config  (<project>/.codabrus/permissions.lisp)
Level 2: Agent config    (agent's :allow/:deny lists)
Level 3: Session state   (user's yes/no answers accumulated during session)
Level 4: Runtime ask     (prompt user, store in session state)
```

Each tool declares its **permission tier**:

| Tier | Examples | Default behavior |
|------|----------|-----------------|
| `:read` | read-file, search, glob | Auto-allow always |
| `:write` | edit-file, write-file | Ask once per session |
| `:execute` | bash, MCP external tools | Ask every time (or once if explicitly pre-approved) |
| `:network` | web-fetch, MCP network tools | Ask once per session |

The permission system is implemented as a **before-hook** on the tool dispatcher:

```lisp
(defgeneric check-permission (permission-set tool args)
  (:documentation "Return :allow, :deny, or :ask."))
```

When the answer is `:ask`, execution blocks (the session actor sends a `permission-request` event to the UI), waits for a `permission-response` message, then proceeds or aborts.

The user's response can be: `:allow-once`, `:allow-session`, `:allow-project`, `:deny-once`, `:deny-session`.

**Guardrail chain** runs before the permission check and can veto silently:
- Secret detection: reject tool args containing strings matching secret patterns (AWS keys, GitHub tokens, etc.)
- Path traversal: reject paths that escape the project root
- Shell injection: warn on suspicious shell argument patterns

Guardrail results are logged and published on the event bus even when no action is taken.

## Consequences

**Good:**
- Safe by default: only `:read` tools run without asking
- Progressive trust: user can promote specific tools to auto-allow per session or project
- Auditable: every permission decision is logged with tool, args, and user choice
- Guardrails are separate from permissions; either can be extended independently

**Neutral:**
- Adds a synchronous wait point in the agent loop (permission ask); the session actor must handle the blocked state cleanly
- Serialized session actor handles this naturally: it simply awaits the permission-response message

**Risk:**
- Overly aggressive prompting will frustrate users and lead to "allow all" fatigue
- Mitigation: pre-approve `:read` and `:write` tiers by default; only `:execute` and `:network` ask; make it easy to promote tools in the TUI with a single keypress
