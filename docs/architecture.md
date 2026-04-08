# Codabrus Architecture

This document describes the intended architecture of Codabrus. It is a living document — as ADRs are written and implemented, sections here grow more concrete.

See [principles.md](principles.md) for the design values that shape every decision here.

---

## System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                          UI Layer                                │
│   ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌────────────┐  │
│   │  REPL /  │   │  TUI     │   │  Web UI  │   │  ACP       │  │
│   │  CLI     │   │(terminal)│   │(Reblocks)│   │(IDE client)│  │
│   └────┬─────┘   └────┬─────┘   └────┬─────┘   └─────┬──────┘  │
└────────┼──────────────┼──────────────┼───────────────┼──────────┘
         │              │              │               │
         └──────────────┴──────┬───────┘───────────────┘
                               │  Session API (Sento messages)
┌──────────────────────────────▼──────────────────────────────────┐
│                     Session Manager                              │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────────┐    │
│  │ Session  │  │ Session  │  │ Session  │  │  Event Bus   │    │
│  │ Actor 1  │  │ Actor 2  │  │ Actor N  │  │  (Sento PS)  │    │
│  └────┬─────┘  └──────────┘  └──────────┘  └──────────────┘    │
└───────┼─────────────────────────────────────────────────────────┘
        │
┌───────▼─────────────────────────────────────────────────────────┐
│                       Agent Core                                 │
│                                                                  │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │  Agent Loop  (process-step protocol)                    │   │
│   │  1. Assemble context (messages + memory + system)       │   │
│   │  2. Call LLM provider                                   │   │
│   │  3. Parse response (text parts, tool-call parts)        │   │
│   │  4. Execute tools via Tool Dispatcher                   │   │
│   │  5. Append results, check loop-exit condition           │   │
│   │  6. Repeat or return                                    │   │
│   └─────────────────────────────────────────────────────────┘   │
│                                                                  │
│   ┌───────────────┐  ┌────────────────┐  ┌──────────────────┐   │
│   │ Context       │  │ Tool           │  │ Subagent         │   │
│   │ Manager       │  │ Dispatcher     │  │ Spawner          │   │
│   │ (compression, │  │ (registry,     │  │ (delegate to     │   │
│   │  cost, tokens)│  │  permissions)  │  │  specialized     │   │
│   └───────────────┘  └────────────────┘  │  agents)         │   │
│                                          └──────────────────┘   │
└──────────────────────────────────────────────────────────────────┘
        │                    │                    │
┌───────▼──────┐   ┌─────────▼──────┐   ┌────────▼───────────────┐
│  LLM         │   │  Tool          │   │  Memory                │
│  Providers   │   │  Ecosystem     │   │  System                │
│              │   │                │   │                        │
│  • Anthropic │   │  Built-in:     │   │  • Global (user-wide)  │
│  • OpenAI    │   │  • read-file   │   │  • Project-scoped      │
│  • Ollama    │   │  • search      │   │  • Session (short-term)│
│  • …         │   │  • edit-file   │   │                        │
│              │   │  • bash        │   │  Storage:              │
│  (via        │   │  • web-fetch   │   │  • Markdown files      │
│  Completions │   │                │   │  • SQLite index        │
│  library)    │   │  MCP tools:    │   │                        │
│              │   │  • auto-disco- │   └────────────────────────┘
│              │   │    vered via   │
│              │   │    MCP protocol│
│              │   │                │
│              │   │  User tools:   │
│              │   │  • SKILL.md    │
└──────────────┘   └────────────────┘
```

---

## Layer Descriptions

### UI Layer

Each UI adapter subscribes to session events via the event bus and sends user messages to a session actor. The adapter knows nothing about the agent loop; it only sees events: `message-added`, `tool-called`, `tool-result`, `message-complete`, `cost-updated`, `error`.

- **REPL/CLI** — simplest adapter; synchronous; used for development
- **TUI** — terminal interface built with `cl-charms` or similar; async, renders streaming output
- **Web UI** — Reblocks server-side components; sessions map to browser tabs
- **ACP** — Agent Client Protocol server; allows IDE plugins to drive sessions

### Session Manager

A top-level Sento actor that owns the registry of active sessions. Responsibilities:
- Create/resume/fork/archive sessions
- Route external messages to the correct session actor
- Maintain the event bus instance

Each **Session Actor** serializes access to one conversation. It holds:
- Message history (list of `message` structs, each with parts)
- Current agent and its configuration
- Permission state for this session
- Accumulated token and cost counters

### Agent Core

The agent loop is a pure function of `(session-state, agent-config, tool-registry, llm-provider) → new-session-state`. It is not a Sento actor itself — the session actor calls it and manages concurrency.

Key sub-components:

**Context Manager** — tracks token counts, computes when compression is needed, calls the compaction agent when the context window fills up.

**Tool Dispatcher** — receives tool-call requests from the LLM response parser, checks permissions, calls `execute-tool` on the appropriate tool, wraps results in `tool-result` parts. Supports parallel execution of independent tool calls.

**Subagent Spawner** — creates a new session actor with a focused agent configuration (e.g., `explore` mode) and a specific task. Returns the result as a `subtask-result` part in the parent session.

### Agent Types

| Agent | Purpose | Tool Access |
|-------|---------|-------------|
| `build` | Main editing agent; full write access | all tools |
| `plan` | Analysis and planning; read-only | read-file, search, web-fetch |
| `explore` | Fast file/code search | read-file, search, glob |
| `compaction` | Summarize long message history | (internal, no tools) |
| `title` | Generate session title | (internal, no tools) |
| User-defined | Configured via `AGENTS.md` | configurable |

Agents are configured in `AGENTS.md` (project-level) or the global config. Each specifies: model, system prompt additions, tool whitelist/blacklist, temperature.

### Memory System

Three scopes, two storage backends:

```
~/.codabrus/memory/global/     ← global, all projects
<project>/.codabrus/memory/    ← project-scoped
<session-id>/                  ← session, ephemeral
```

Memory entries are Markdown files with YAML frontmatter (same format as Claude Code's auto-memory). An SQLite index enables semantic search via embeddings or keyword search.

Retrieval is automatic: at the start of each agent loop iteration, relevant memories are injected into the system prompt.

### Tool Ecosystem

**Built-in tools** live in `src/tools/`. Each file = one package = one tool, following the existing pattern.

**MCP tools** are discovered via the Model Context Protocol client. When the session starts, configured MCP servers are queried for their tool manifests. These are dynamically registered in the tool registry for this session.

**User tools** (SKILL.md) are Lisp snippets or scripts declared in the project's `SKILL.md`. The agent can invoke them by name.

### LLM Providers

The `completions` library already abstracts LLM calls. We extend this with:
- A registry of providers keyed by ID (`anthropic`, `openai`, `ollama`, …)
- Per-agent model selection
- Token counting that feeds back to the Context Manager
- Cost accumulation (price-per-token config per model)

---

## Key Data Structures

### Message and Parts

```lisp
(defclass message ()
  ((id          :initarg :id)           ; unique, monotonic
   (role        :initarg :role)         ; :user | :assistant | :system
   (parts       :initarg :parts)        ; list of part instances
   (time-created :initarg :time-created)))

;; Abstract base — all part types inherit from it
(defclass part () ())

(defclass text-part (part)
  ((content :initarg :content)))

(defclass tool-call-part (part)
  ((tool-id :initarg :tool-id)
   (call-id :initarg :call-id)
   (args    :initarg :args)))

(defclass tool-result-part (part)
  ((call-id  :initarg :call-id)
   (output   :initarg :output)
   (metadata :initarg :metadata)))

(defclass reasoning-part (part)
  ((content :initarg :content)))

(defclass subtask-part (part)
  ((agent-id :initarg :agent-id)
   (task     :initarg :task)
   (result   :initarg :result)))   ; nil until complete

(defclass compaction-part (part)
  ((summary      :initarg :summary)
   (tokens-saved :initarg :tokens-saved)))

(defclass step-end-part (part)
  ((finish-reason :initarg :finish-reason) ; :tool-calls | :stop | :error
   (tokens-in     :initarg :tokens-in)
   (tokens-out    :initarg :tokens-out)
   (cost-usd      :initarg :cost-usd)))
```

### Session State

```lisp
(defclass session ()
  ((id               :initarg :id)
   (project-dir      :initarg :project-dir)      ; pathname
   (messages         :initarg :messages)          ; list of message instances
   (agent            :initarg :agent)             ; agent-config instance
   (permissions      :initarg :permissions)       ; permission-set instance
   (context-tokens   :initarg :context-tokens)    ; accumulated integer
   (context-cost-usd :initarg :context-cost-usd)  ; accumulated float
   (status           :initarg :status)            ; :idle | :running | :waiting-for-permission | :error
   (created-at       :initarg :created-at)
   (updated-at       :initarg :updated-at)))
```

### Agent Config

```lisp
(defclass agent-config ()
  ((id             :initarg :id)
   (name           :initarg :name)
   (model          :initarg :model)           ; e.g. "claude-opus-4-6"
   (provider       :initarg :provider)        ; e.g. :anthropic
   (system-prompts :initarg :system-prompts)  ; list of strings appended to base prompt
   (tools          :initarg :tools)           ; list of tool-id (nil = all)
   (denied-tools   :initarg :denied-tools)    ; list of tool-id
   (temperature    :initarg :temperature)
   (max-tokens     :initarg :max-tokens)))
```

### Permission Set

```lisp
(defclass permission-set ()
  ((allow        :initarg :allow)        ; list of tool-id (nil = allow all)
   (deny         :initarg :deny)         ; list of tool-id
   (auto-approve :initarg :auto-approve) ; list of tool-id (never ask)
   (ask-once     :initarg :ask-once)))   ; alist of tool-id → :allowed | :denied
```

---

## Concurrency Model

Sento actors handle all mutable state. The pattern:

```
[UI adapter]
    │ ask!(:run-prompt "...")
    ▼
[Session Actor]  ← serializes all mutations to session state
    │ calls synchronously
    ▼
[Agent Core loop]  ← pure, no side effects on actors directly
    │ publishes events
    ▼
[Event Bus]  ← fan-out to all subscribers
    ├──► [UI adapter] (streaming output)
    ├──► [Logger]
    └──► [Cost Tracker]
```

Tool calls that are independent can be fanned out to a thread pool via `bt:make-thread` or Sento's async patterns, then joined before appending results.

---

## Security Model

1. **Read-only by default** — tools that only read data never require confirmation
2. **Write operations ask once per session** (or per-project if user prefers)
3. **Execute operations** (bash, MCP external) ask every time unless explicitly auto-approved
4. **Guardrail chain** — pluggable validators on both input (user message) and output (LLM response + tool args):
   - Secret detection (API keys in tool args)
   - Path traversal detection
   - Shell injection detection
5. **Sandboxed bash** — optional, runs in a restricted shell or container

---

## Configuration Files

| File | Scope | Purpose |
|------|-------|---------|
| `~/.codabrus/config.lisp` | Global | Providers, models, global defaults |
| `<project>/AGENTS.md` | Project | Agent definitions, custom system prompts |
| `<project>/SKILL.md` | Project | User-defined skills/tools |
| `<project>/.codabrus/permissions.lisp` | Project | Pre-approved tool permissions |
| `<project>/.codabrus/memory/` | Project | Project memory store |

---

## ADR Index

| ADR | Title | Status |
|-----|-------|--------|
| [0001](adr/0001-actor-model-with-sento.md) | Use Sento actor model for session concurrency | Proposed |
| [0002](adr/0002-part-based-message-format.md) | Part-based message format for streaming and heterogeneity | Proposed |
| [0003](adr/0003-memory-as-markdown-files.md) | Memory stored as Markdown files with SQLite index | Proposed |
| [0004](adr/0004-mcp-tool-integration.md) | MCP protocol for tool ecosystem integration | Proposed |
| [0005](adr/0005-permission-layer.md) | Multi-level permission system for tool execution | Proposed |
