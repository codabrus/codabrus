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

## 8. Headless and Automation-Friendly

The agent can run fully unattended, without a human operator present. In non-interactive (headless) mode:

- No confirmation prompts are issued; tool permissions are declared upfront in configuration
- The process exits with a meaningful code: `0` = task completed, `1` = task failed, `2` = agent could not proceed without human input
- Output is structured (JSON Lines or plain text) suitable for CI log parsers and dashboards
- A maximum-turns and token-budget limit prevents runaway cost on long-running jobs
- All tool calls, results, and LLM turns are written to a structured audit log

This makes Codabrus usable as a step in CI pipelines, scheduled cron jobs, and programmatic orchestration — not just interactive use.

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
2. Non-interactive (headless) mode for CI pipelines and scripted automation
3. MCP tool integration (ecosystem access)
4. Terminal UI and Web UI
5. Subagent delegation
6. Per-agent LLM and prompt configuration
7. Context compression for long sessions
8. Context size and cost tracking
9. Parallel sessions
10. User skills via `SKILL.md`
11. Agent configuration via `AGENTS.md`
12. Agent Client Protocol (ACP) for IDE integration
13. Language Server Protocol (LSP) for semantic code understanding
14. Distributed tool/agent execution on remote hosts
