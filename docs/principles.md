# Codabrus Design Principles

This document defines the foundational principles that guide all architectural and implementation decisions in Codabrus.

## 1. Spec-Driven Development

All non-trivial changes begin with an Architecture Decision Record (ADR) in `docs/adr/NNNN-title.md`. Code follows the spec, not the other way around. This ensures decisions are recorded with their context and rationale, making the system auditable and teachable.

## 2. Modularity and Composability

The system is built from small, independently useful components that can be combined freely. Interfaces between components are explicit protocols (CLOS generics). No component has hidden dependencies. A new tool, a new UI, or a new LLM provider can be added without modifying unrelated code.

## 3. Core Independence

The agent processing core (the loop that calls the LLM, dispatches tool calls, and accumulates state) knows nothing about:
- How the user interacts (TUI, Web UI, ACP, REPL)
- Which specific tools are available
- Which LLM provider is used
- How messages are persisted

These concerns are injected at construction time. The core is a pure state machine.

## 4. Project-Aware Memory

The assistant maintains memory at two scopes:

- **Global memory** — knowledge about technologies, patterns, and conventions that apply across all projects (e.g., "in Rust, prefer `?` over `unwrap`")
- **Project memory** — project-specific knowledge: goals, decisions, constraints, codebase idioms

Both scopes are searchable. Project memory is relative to a project root directory. Global memory lives in the user's configuration directory.

## 5. Distributed by Design

Individual actors (sessions, tools, subagents) communicate via message passing using the Sento actor library. The interface between actors does not assume co-location. A tool executor, an LLM caller, or an entire subagent can run on a remote host by changing the transport, not the logic.

## 6. Transparency and Debuggability

Everything that happens during agent execution is observable:
- All LLM calls, tool invocations, and state transitions are logged via `log4cl`
- The full state of every session is accessible from the REPL at any time
- Structured events are published on the event bus so any subscriber can trace execution
- Cost and token usage are tracked per request and per session

## 7. Safety and Guardrails

The assistant distinguishes between read-only and write/execute operations. Destructive or irreversible actions (shell execution, file deletion, external API calls) require explicit user confirmation unless the user has pre-authorized them. The permission system has layers: global defaults, project configuration, session overrides, and per-request prompts. Input and output can be validated by configurable guardrail chains.

## Technology Constraints

| Concern | Library |
|---------|---------|
| Core language | Common Lisp (SBCL primary) |
| Actor model / concurrency | Sento |
| Web UI | Reblocks |
| LLM abstraction | 40ants-ai-agents + Completions |
| Async event bus | Sento pub/sub |
| Persistence | SQLite via cl-dbi or files |
| Testing | Rove |
| CI | 40ants-ci |

## Capabilities Roadmap Principles

The following capabilities guide the long-term feature set. They are listed roughly in dependency order; each depends on the ones above it being solid:

1. Autonomous code writing checked by tests
2. MCP tool integration (ecosystem access)
3. Terminal UI and Web UI
4. Subagent delegation
5. Per-agent LLM and prompt configuration
6. Context compression for long sessions
7. Context size and cost tracking
8. Parallel sessions
9. User skills via `SKILL.md`
10. Agent configuration via `AGENTS.md`
11. Agent Client Protocol (ACP) for IDE integration
12. Language Server Protocol (LSP) for semantic code understanding
13. Distributed tool/agent execution on remote hosts
