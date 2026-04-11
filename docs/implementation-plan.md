# Codabrus Implementation Plan

This roadmap moves from the current working prototype toward the full architecture described in [architecture.md](architecture.md), following the [principles](principles.md). Each phase produces a working, testable system — no phase leaves things broken.

---

## Current State (Baseline)

- Single-turn agent loop via `40ants-ai-agents:process`
- Three tools: `read-file`, `search`, `edit-file` (with 7-stage fuzzy replacer)
- REPL-only interface: `(codabrus:test-ai "...")`
- No sessions, no memory, no persistence
- Tests: Rove, covering `edit-file` in detail

---

## Phase 1 — Solid Core (Priority: Now)

Goal: make the agent genuinely useful for autonomous coding on a real project. No architectural changes yet — improve what exists.

### 1.1 Bash Tool ✓
- Add `src/tools/bash.lisp` — run shell commands with a 30s timeout
- No sandboxing yet; output capped at 4000 chars
- Required permission tier: `:execute`
- This enables: running tests, `git status`, compiling code

### 1.2 Multi-Turn Session State (no persistence) ✓
- Refactor `test-ai` into a `session` struct holding message history
- `run-session(session, message) → session` — adds message, runs loop, returns updated session
- Session survives across multiple calls in the same Lisp image
- No Sento yet; synchronous and single-threaded

### 1.3 Context Tracking ✓
- Count tokens in/out per LLM call (use Completions' response metadata)
- Accumulate total cost per session
- Print summary at end of each turn: `[tokens: 1234 in / 456 out | cost: $0.003]`

### 1.4 Test Coverage for New Tools ✓
- Tests for `bash` tool: output capture, timeout, error handling
- Integration smoke test: `test-ai` against a real small project

**ADRs needed:** none (all extensions of existing patterns)

---

## Phase 2 — Non-Interactive (CI) Mode

Goal: Codabrus can be invoked from a shell script or CI pipeline without any human present.

This phase is deliberately placed before session persistence and actors — it requires only Phase 1's bash tool and context tracking, and delivers immediate practical value.

### 2.1 CLI Entry Point ✓

- Binary `codabrus` (or `qlot exec sbcl --script codabrus.lisp`) with a minimal argument parser
- `codabrus --prompt "fix the failing tests" [project-dir]` — run one task and exit
- `codabrus --session <id> --prompt "..." ` — continue an existing session (once Phase 3 lands)
- `--model <id>` — override the default model for this run

### 2.2 Headless Mode Flag ✓

- `--non-interactive` flag (or detect `CI=true` env var) activates headless mode
- In headless mode: no confirmation prompts; all tool permissions are auto-approved according to a pre-set policy (default: allow `:read` and `:write`, deny `:execute` unless `--allow-execute` is set)
- Any tool call that would normally ask the user instead logs a warning and either proceeds (if allowed) or fails the session with exit code `2`

### 2.3 Exit Codes and Structured Output

| Code | Meaning |
|------|---------|
| `0` | Agent completed the task (finished without tool-call loop) |
| `1` | Agent failed: LLM error, tool error, or max-turns exceeded |
| `2` | Agent stalled: needed human input but none available |

- `--output json` — emit JSON Lines to stdout: one object per event (`text`, `tool-call`, `tool-result`, `cost`, `finish`)
- `--output plain` (default) — human-readable, same as current REPL output
- Final cost summary always printed to stderr (not stdout) so it doesn't pollute piped output

### 2.4 Budget Limits

- `--max-turns N` — abort after N LLM round-trips (default: 20)
- `--max-cost-usd F` — abort if accumulated cost exceeds the threshold
- When a limit is hit: finish cleanly (flush output, write audit log), exit with code `1`

### 2.5 Audit Log

- `--audit-log path/to/run.jsonl` — write every LLM call, tool invocation, result, and cost entry to a JSONL file
- Suitable for post-run inspection, billing reconciliation, and debugging failed CI runs
- Written incrementally (flushed after each event) so partial logs survive crashes

### 2.6 GitHub Actions Example

```yaml
- name: AI code review and fix
  run: |
    codabrus \
      --non-interactive \
      --allow-execute \
      --max-turns 30 \
      --max-cost-usd 0.50 \
      --audit-log /tmp/codabrus-run.jsonl \
      --prompt "Run the tests. If any fail, fix them and run again."
```

**ADRs needed:** none (extensions of Phase 1 patterns; permission policy is a simplified precursor to ADR-0005)

---

## Phase 3 — Session Management and Persistence

Goal: sessions survive Lisp image restarts; multiple sessions can coexist.

### 3.1 Session Persistence
- ADR: choose SQLite (cl-dbi + cl-sqlite) or plain files (each session = a directory of JSONL files)
- Implement `save-session` / `load-session`
- Session identified by a UUID
- Message history serialized as a sequence of JSONL lines (one per part)

### 3.2 Part-Based Message Format
- Implement the data structures from ADR-0002
- Adapter layer: convert part-based history to the list format `40ants-ai-agents` expects
- All existing tools return their output wrapped in `tool-result-part`

### 3.3 Session CLI
- `codabrus new [project-dir]` — start a new session
- `codabrus resume [session-id]` — continue an existing session
- `codabrus list` — show sessions with last message and cost
- Reads from stdin, prints to stdout; structured for easy piping

**ADRs needed:** extend ADR-0002 (serialization format)

---

## Phase 4 — Sento Actor Model

Goal: the agent loop runs in an actor; multiple sessions can run concurrently in the same process.

### 4.1 Session Actor
- Implement `session-actor` using Sento
- Messages: `(:run message)`, `(:abort)`, `(:get-state)`, `(:subscribe callback)`
- Session actor calls the agent loop synchronously within its message handler
- Event bus: simple pub/sub actor; session actor publishes events as parts are produced

### 4.2 Session Manager Actor
- Top-level actor: `(:new-session config)`, `(:resume session-id)`, `(:list-sessions)`
- Holds a registry of live session actors

### 4.3 Parallel Tool Execution
- When the LLM returns multiple tool calls simultaneously, dispatch each to a separate Bordeaux-Threads thread
- Join all threads before appending results
- Cap parallelism at 4 concurrent tool calls

**ADRs needed:** ADR-0001 implemented

---

## Phase 5 — Memory System

Goal: the agent accumulates and retrieves knowledge across sessions and projects.

### 5.1 Memory Store
- Implement memory file format (ADR-0003): Markdown + YAML frontmatter
- `store-memory(scope, name, content, tags)` — write memory file, update MEMORY.md index
- `retrieve-memories(scope, query, top-k)` — FTS5 keyword search via SQLite
- Memory store at `~/.codabrus/memory/` (global) and `<project>/.codabrus/memory/` (project)

### 5.2 Memory Injection
- Context manager calls `retrieve-memories` at loop start
- Top-3 relevant entries prepended to system prompt as `<memory>` blocks
- Memory injection is logged and visible in debug mode

### 5.3 Memory Tool
- Add `src/tools/remember.lisp` — the agent can explicitly store a memory
- `(remember-tool "name" "content" "global|project")` — stores a memory entry

**ADRs needed:** ADR-0003 implemented

---

## Phase 6 — Permission System and Guardrails

Goal: the agent is safe to run on real projects without surprises. Also upgrades the simplified headless policy from Phase 2 to the full configurable cascade.

### 6.1 Permission Layer
- Implement permission cascade from ADR-0005
- Tool tiers: `:read`, `:write`, `:execute`, `:network`
- Permission state stored in session struct
- CLI prompt: `Allow bash("git status")? [y/n/always/never]`

### 6.2 Guardrail Chain
- Secret detection: warn if tool args contain patterns matching AWS/GH/Anthropic key formats
- Path traversal detection: reject `..` paths that escape project root
- Guardrail violations logged; optionally block or just warn

### 6.3 Project Config
- `<project>/.codabrus/config.lisp` — pre-approve tool tiers, set model, override system prompt
- Loaded automatically when a session is started in that project

**ADRs needed:** ADR-0005 implemented

---

## Phase 7 — MCP Integration

Goal: the agent can use tools from the MCP ecosystem (GitHub, databases, web, etc.)

### 7.1 MCP Client
- Implement MCP client: connect to stdio-based MCP servers, fetch manifests, call tools
- Dynamic tool registration: MCP tools appear in the tool registry for this session
- Configuration in `<project>/.codabrus/mcp.lisp`

### 7.2 MCP Server (Codabrus as MCP server)
- Expose Codabrus's built-in tools via MCP protocol
- Other agents or IDE plugins can call `read-file`, `search`, `edit-file` over MCP
- Re-uses `libs/lisp-dev-mcp/` infrastructure

**ADRs needed:** ADR-0004 implemented

---

## Phase 8 — Context Compression

Goal: sessions can run for hours without hitting context limits.

### 8.1 Context Window Monitoring
- Track token count against model's context limit
- Emit `context-warning` event at 75% capacity, `context-overflow` at 90%

### 8.2 Compaction Agent
- Dedicated `compaction` agent (read-only, no tools)
- When overflow detected: summarize the message history (keeping system message and last 4 turns intact)
- Summary stored as a `compaction-part` in the message history
- Old messages replaced by the summary for subsequent LLM calls

### 8.3 Sliding Window Fallback
- Simple fallback: drop oldest non-system messages until under threshold
- Used when the compaction agent itself would exceed the context limit

---

## Phase 9 — Multi-Agent Support

Goal: the agent can delegate sub-tasks to specialized agents.

### 9.1 Agent Types
- Implement `plan`, `explore`, `build`, `compaction` agent configs
- Each has its own system prompt, tool allowlist, and optionally a different model

### 9.2 Task Tool
- Add `src/tools/task.lisp` — the `build` agent delegates to subagents
- `(task-tool "explore" "find all uses of defun-tool in the codebase")` — spawns a session actor with the `explore` agent, returns its final response

### 9.3 AGENTS.md Support
- Parse `AGENTS.md` from project root at session start
- Register custom agents defined therein
- Format: frontmatter per agent block (name, model, system, tools)

---

## Phase 10 — Terminal UI

Goal: a proper interactive terminal interface.

### 10.1 TUI Framework
- Evaluate: `cl-charms` (ncurses) or `croatoan` (ANSI/xterm)
- Decision: write ADR once evaluation is done
- Basic layout: message history (scrollable), input line, status bar (model, tokens, cost)

### 10.2 Streaming Output
- Subscribe to session event bus
- Render `text-part` events character-by-character as they arrive
- Show spinner during LLM call
- Show tool calls inline: `[calling read-file: src/core.lisp]`

### 10.3 Permission Prompts in TUI
- Inline permission prompt: `Allow bash("make test")? [y]es [n]o [a]lways [N]ever`
- Single keypress, non-blocking for other UI updates

---

## Phase 11 — Web UI

Goal: browser-based interface for project dashboards and sharing.

### 11.1 Reblocks Integration
- Reblocks server starts alongside the session manager
- Each browser tab = one session (or resumes an existing one)
- Components: session list sidebar, chat view, tool call renderer, cost dashboard

### 11.2 Streaming via SSE
- Server-Sent Events for real-time message streaming
- Reblocks HTMX integration for partial updates

### 11.3 Session Sharing
- Optional: share a read-only view of a session via URL
- Shareable link shows the full conversation including tool calls

---

## Phase 12 — ACP (Agent Client Protocol)

Goal: IDE plugins can drive Codabrus like Claude Code drives VS Code.

### 12.1 ACP Server
- HTTP server exposing ACP endpoints
- `POST /session` — create/resume session
- `POST /session/:id/message` — send message, stream response via SSE
- `GET /session/:id/events` — SSE stream of session events

### 12.2 IDE Plugin Protocol
- Document the ACP endpoints so third-party plugins can be written
- Provide a reference client in `sdk/` (Common Lisp first, possibly JSON schema for others)

---

## Phase 13 — Skills (SKILL.md)

Goal: users can add custom tools/skills to a project without modifying Codabrus source.

### 13.1 SKILL.md Parser
- Parse `SKILL.md` from project root
- Each skill defined as a shell command or Lisp snippet with a name and description
- Skills registered as tools in the session

### 13.2 Skill Execution
- Shell skills: run via bash tool with the skill's arguments
- Lisp skills: `load` and `funcall` within the session's package
- Skill tool gets `:execute` permission tier

---

## Phase 14 — LSP Integration (stretch goal)

Goal: the agent understands code semantically, not just textually.

### 14.1 LSP Client
- Connect to language servers (clangd, rust-analyzer, clojure-lsp, sbcl-lsp)
- Expose: go-to-definition, find-usages, hover-type, rename-symbol as tools
- LSP server started lazily when the agent first calls an LSP tool

### 14.2 Semantic Edit Tool
- Use LSP rename/refactor operations when available instead of text replacement
- Falls back to the existing 7-stage replacer chain when LSP is unavailable

---

## Phase 15 — Distributed Execution (stretch goal)

Goal: tools and agents can run on remote hosts.

### 15.1 Remote Tool Execution
- Sento's remote actor transport: a tool executor can be an actor on another machine
- Configuration: `(:tool-host "gpu-box.local" :tools (:bash :code-search))`

### 15.2 Remote Subagents
- Spawn a subagent session on a remote Codabrus instance
- Useful for: sandboxed execution, specialized hardware, air-gapped environments

---

## Priorities Summary

| Phase | Value | Effort | Do Next? |
|-------|-------|--------|---------|
| 1 — Solid Core | High | Low | **Yes** |
| 2 — CI / Headless Mode | High | Low | **Yes** |
| 3 — Sessions + Persistence | High | Medium | After 2 |
| 4 — Sento Actors | High | Medium | After 3 |
| 5 — Memory | High | Medium | After 4 |
| 6 — Permissions | High | Low | During 4 |
| 7 — MCP | High | Medium | After 5 |
| 8 — Compaction | Medium | Medium | After 7 |
| 9 — Multi-Agent | Medium | Medium | After 8 |
| 10 — TUI | Medium | High | After 9 |
| 11 — Web UI | Medium | High | After 10 |
| 12 — ACP | Low | Medium | After 11 |
| 13 — Skills | Medium | Low | After 9 |
| 14 — LSP | Low | High | Stretch |
| 15 — Distributed | Low | High | Stretch |
