# ADR-0002: Part-Based Message Format

**Status:** Proposed  
**Date:** 2026-04-08

## Context

Currently Codabrus represents messages as opaque strings (user message in, tool XML out, assistant message out). This is sufficient for a single-turn REPL demo but fails for:

1. **Streaming** — the UI needs to display text as it arrives, not after the full response
2. **Tool call visibility** — the UI should show "calling read-file…" before the result arrives
3. **Cost display** — token counts and cost need to be attached to a specific LLM call, not the whole session
4. **Compaction** — the compaction agent needs to know which messages are compactable vs pinned
5. **Subagents** — a subtask delegated to a subagent needs to be represented in the parent session's history
6. **Reasoning tokens** — Claude's extended thinking produces reasoning blocks that are separate from text

## Decision

Adopt a **part-based message format** where each message is a list of typed parts:

```lisp
(defclass message ()
  ((id         :type integer)
   (role       :type (member :user :assistant :system))
   (parts      :type list)     ; list of part instances
   (created-at :type local-time:timestamp)))

;; Part types:
(defclass text-part         () ((content :type string)))
(defclass tool-call-part    () ((tool-id :type string)
                                (call-id :type string)
                                (args    :type list)))
(defclass tool-result-part  () ((call-id  :type string)
                                (output   :type string)
                                (metadata :type list)))
(defclass reasoning-part    () ((content :type string)))
(defclass subtask-part      () ((agent-id :type string)
                                (task     :type string)
                                (result   :type (or null string))))
(defclass compaction-part   () ((summary      :type string)
                                (tokens-saved :type integer)))
(defclass step-end-part     () ((finish-reason :type keyword)
                                (tokens-in     :type integer)
                                (tokens-out    :type integer)
                                (cost-usd      :type float)))
```

Each part type generates a corresponding event on the event bus as it is produced, enabling streaming UIs to react immediately.

## Consequences

**Good:**
- Every piece of content has an explicit type; UIs can render each differently
- Token/cost data is attached to `step-end-part`, not lost
- Compaction can skip pinned parts (e.g., the initial `system` message)
- Subagent results are first-class in the message history
- Serialization to/from SQLite is straightforward: one row per part

**Neutral:**
- More data structures than the current string approach
- The `40ants-ai-agents` library currently deals in simpler structures; we may need to wrap or extend it

**Risk:**
- Requires changes to how `40ants-ai-agents:process` is called
- Mitigation: implement a thin adapter layer that converts our part-based messages to whatever `40ants-ai-agents` expects, and converts responses back to parts
