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

### Web UI (Reblocks)

The Web UI is a Reblocks application defined in `src/frontend/`. It uses the new-style Reblocks API with `reblocks-ui2` widgets, Tailwind CSS themes, and `40ants-routes` routing.

#### File structure

```
src/frontend/
  app.lisp              — defapp with routes (page routes + SSE routes)
  server.lisp           — start/stop functions
  routes.lisp           — custom route classes (SSE streaming)
  pages/
    main.lisp           — main page widget (diagram + sidebar + prompt)
  widgets/
    x6-diagram.lisp     — X6 diagram widget with SSE client
    prompt-input.lisp   — text input + Send/Reset buttons
    message-popup.lisp  — popup for node content (tool calls, results)
    thinking-sidebar.lisp — streaming LLM output sidebar
  diagram/
    builder.lisp        — builds diagram data (nodes/edges) from messages
    session.lisp        — LLM session management, stream buffer
  x6/                   — AntV X6 JS library (Vite/IIFE build)
```

#### Server-Sent Events (SSE) for live updates

The Web UI uses SSE to push real-time updates from the server to the browser. Two SSE endpoints serve different purposes:

| Endpoint | Route class | Purpose |
|----------|------------|---------|
| `/diagram-events` | `diagram-sse-route` | Diagram node/edge updates |
| `/stream-events` | `stream-sse-route` | Streaming LLM text to sidebar |

##### Diagram SSE (`/diagram-events`)

**How it works:**

```
Browser                              Server
  │                                    │
  │─── GET / ─────────────────────────>│  Reblocks page route
  │<── HTML + diagram.js ─────────────│  Widget render + dependencies
  │                                    │
  │─── EventSource /diagram-events ──>│  SSE route (diagram-sse-route)
  │                                    │  clack-sse:serve-sse opens stream
  │<══ event: init-diagram ═══════════│  Full diagram state (all nodes + edges)
  │    {"nodes":[...],"edges":[...]}   │
  │                                    │
  │  JS: graph.dispose() + initDiagram │  Clear and recreate graph from data
```

**Server side** (`src/frontend/routes.lisp`):

1. A custom route class `diagram-sse-route` inherits from `40ants-routes/route:route`.
2. `reblocks/routes:serve` is specialized on this class to return `(clack-sse:serve-sse 'handler)`.
3. The stream handler polls `get-session-messages()` every 1 second.
4. When the message count changes, it builds diagram data via `build-diagram-data` and sends an `init-diagram` event with the full JSON (all nodes and edges).
5. The client disposes the old graph and creates a fresh one from the data.

**Client side** (`src/frontend/widgets/x6-diagram.lisp`):

1. The widget's `get-dependencies` serves the X6 IIFE bundle as a local JS dependency.
2. The `render` method outputs a container `<div>` and an inline `<script>` that:
   - Initializes the X6 graph via `initDiagram()` and stores it as `window.codabrusGraph`.
   - Registers `graph.on('node:click')` handler that triggers a Reblocks action to show a popup with node details.
   - Creates an `EventSource` connected to `/diagram-events`.
   - On `init-diagram`: disposes old graph, creates new one via `resetDiagram()`, re-registers click handler.
   - Auto-scrolls viewport to the rightmost node if it's outside the visible area.

**Diagram event format:**

```
event: init-diagram
data: {"nodes":[{"id":"m0","x":80,"y":100,...},...],"edges":[{"source":"m0","target":"m2","router":{"name":"manhattan"},"connector":{"name":"rounded"}},...]}

```

Edges use Manhattan routing with rounded connectors. Main chain edges connect via `right→left` anchors, tool branch edges via `bottom→top` anchors.

##### Streaming SSE (`/stream-events`)

The thinking sidebar shows real-time LLM output as tokens arrive from the API.

**Data flow:**

```
LLM API (streaming HTTP)
  → streaming-callback (called per text chunk)
    → *stream-buffer* (thread-safe, protected by mutex)
      → SSE poll (every 100ms)
        → EventSource in browser sidebar
```

**Server side** (`src/frontend/routes.lisp`):

1. `stream-sse-route` handles `/stream-events`.
2. On connect: sends `stream-clear` to reset sidebar.
3. Poll loop (100ms interval):
   - Reads chunks from `get-stream-chunks()` (returns and clears buffer).
   - If chunks exist: sends `stream-chunk` event with escaped text.
   - Tracks `prev-status` to detect transitions:
     - `:free` → busy: sends `stream-clear` (new request started).
     - Busy → `:free`: sends `stream-done` once (agent finished).
4. Text is SSE-encoded: newlines become `\n` (literal backslash-n) to avoid SSE frame splitting.

**Client side** (`src/frontend/widgets/thinking-sidebar.lisp`):

1. Renders a dark terminal-style container (`bg-gray-900`, `text-gray-200`, `font-mono`).
2. Inline `<script>` creates `EventSource` on `/stream-events`.
3. Event handlers:
   - `stream-chunk`: decodes `\n` → newline, appends text node to container, auto-scrolls.
   - `stream-clear`: clears container text.
   - `stream-done`: shows "done" status badge.

**Streaming callback chain** (`src/frontend/diagram/session.lisp`):

1. `streaming-callback` — locked append to `*stream-buffer*` (mutex-protected).
2. `get-stream-chunks` — locked read-and-clear of buffer.
3. `clear-stream-buffer` — locked clear, called before each new LLM request.
4. The callback is passed through: `session.lisp` → `make-llm-agent` → `llm-agent` slot → `get-single-completion :streaming-callback`.

**SSE events for streaming:**

```
event: stream-clear
data: 

event: stream-chunk
data: Hello! I'll help you with that.\nLet me check...

event: stream-done
data: 

```

**Key libraries:**

| Library | Purpose |
|---------|---------|
| `reblocks` | Web framework (new-style API with defapp routes, page-constructor) |
| `reblocks-ui2` | Widget system with themed rendering (Tailwind) |
| `40ants-routes` | Routing with `defroutes`, `get`, `page`, custom route classes |
| `clack-sse` | SSE streaming for Clack (returns async response function) |
| `AntV X6` | JavaScript diagram library (bundled as IIFE via Vite) |

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

### On-completion Callbacks

Actors that perform async work (tool execution, sub-dispatching) notify their parent via an `:on-completion` callback. The `callback-type` (defined in `src/actors/callbacks.lisp`) accepts:

| Type | Behaviour |
|------|-----------|
| `sento.actor:actor` | Sends message via `act:ask` |
| `string` | Resolves actor by name in `*actor-system*`, then sends message |
| `symbol` (fbound) | Calls `(symbol-function sym)` with the message |
| `function` | Calls `(funcall fn message)` |

Every callback invocation follows a uniform protocol: the message is a list whose first element is a **keyword** identifying the event type (e.g. `:completed`), followed by **keyword-value pairs** carrying event-specific data. For example:

```lisp
(:completed :actor <dispatcher> :tools (<tool1> <tool2>))
```

For forward compatibility, message handlers must accept unknown keyword arguments. Actor methods use `&allow-other-keys` in their lambda lists, and plain functions passed as callbacks should likewise use `(&key &allow-other-keys)` so that new keys can be added without breaking existing consumers.

The calling actor passes its callback as `:on-completion` to the `:run` message. The child stores it and calls `call-callback` when finished. This composes: a `tools-dispatcher` can be a child of another `tools-dispatcher`, forming a tree of parallel work with cascading completion.

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
| [0008](adr/0008-reblocks-web-ui.md) | Reblocks Web UI with SSE for live updates | Proposed |
