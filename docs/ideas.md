# Codabrus Ideas

Ideas that emerged during architectural planning. Not all of these will be built, but they are worth remembering.

---

## Agent Loop Ideas

**Doom-loop detection** — if the agent calls the same tool with the same arguments 3 times in a row, pause and ask the user. OpenCode does this; it prevents the agent from spinning in circles on a problem it cannot solve.

**Plan-then-build mode** — before the agent starts making edits, it first runs in `:plan` mode (read-only) to produce a short bulleted plan, shows it to the user for approval, then switches to `:build` mode. This makes the agent's intentions explicit before it touches files.

**Structured output tool** — if the user (or another agent) asks for a response conforming to a JSON schema, inject a special `structured-output` tool that the LLM must call; the result is validated against the schema before being returned. Useful for programmatic use of the agent.

**Agent-to-agent delegation protocol** — beyond simple subagents, define a protocol where one Codabrus instance can ask another instance (possibly on a remote machine) to handle a task. Return value is a structured result that the calling agent can reason about.

---

## Memory Ideas

**Memory decay** — memories get a "confidence" score that decreases over time unless reinforced. Stale memories are automatically archived. Prevents the memory store from filling up with outdated information.

**Memory from git blame** — when the agent reads a file, it could optionally scan `git log --follow` for the last 10 commits touching that file and extract intent/context into session memory. Helps the agent understand why code is the way it is.

**Cross-project memory deduplication** — when writing a project memory, check if the same fact is already in global memory. If so, don't duplicate; instead, create a reference.

**Memory as RAG** — instead of prepending top-K memories verbatim, embed them and insert only the most semantically similar ones based on the current query. Requires an embedding model. Claude's API has text embedding; Ollama runs locally.

---

## Tool Ideas

**`glob` tool** — list files matching a pattern within the project. Currently the agent has to use search for this, which is noisier. A dedicated glob tool returns only paths.

**`diff` tool** — show git diff for a file or the whole project. Useful when the agent wants to review its own changes before finishing.

**`undo-edit` tool** — revert the last N edits made by the agent in this session (using git). Makes destructive edits recoverable without the user manually running git.

**`run-tests` tool** — a specialized wrapper around bash for running the project's test suite. Knows about common test runners (rove, pytest, cargo test, go test) and formats output in a way that's easy for the LLM to parse.

**`web-search` tool** — query a search engine for documentation or error messages. Can be backed by SearXNG (self-hosted) or Brave/Perplexity API. Higher fidelity than web-fetch for discovery.

**`embed-snippet` tool** — the agent inserts a new code snippet (function, class, config block) into the right place in a file, determined semantically (after the last function, inside a specific class, etc.), without needing to specify the exact insertion point as a string.

---

## UI Ideas

**Session bookmarks** — the user can bookmark important moments in a session (e.g., "this is where I understood the bug") with a note. Bookmarks appear in the session timeline view.

**Cost projections** — given the current context size and typical session length, estimate the total cost of the session. Show as a small indicator in the TUI status bar.

**Replay mode** — replay a saved session step-by-step, pausing at each tool call to inspect what the agent was thinking. Useful for debugging and teaching.

**Diff view in TUI** — after each `edit-file` call, show the diff inline in the chat (colored additions/deletions). The user can `[r]eject` the edit directly from the TUI.

**Web UI: project dashboard** — aggregate view across all sessions for a project: total cost, files touched, open tasks, recent activity. Like a GitHub insights page but for AI work.

---

## Architecture Ideas

**Snapshot/restore** — before a risky sequence of operations (e.g., a large refactor), the agent takes a git snapshot (stash or branch). If the operation fails or the user rejects the result, one command restores the snapshot.

**Session forking** — the user can fork a session at any point to try an alternative approach. Both forks see the same history up to the fork point but diverge afterward. OpenCode supports this.

**Hot-reload agent config** — if `AGENTS.md` or `~/.codabrus/config.lisp` changes while a session is running, the session actor reloads the config on the next turn without restarting.

**Token budget per turn** — the user can set a per-turn token budget (e.g., 2000 output tokens). The agent is instructed to produce a result within that budget. Prevents runaway responses.

**Rate limit awareness** — track API rate limits (requests per minute, tokens per minute) and back off gracefully with a retry-after delay instead of crashing.

**Multi-modal input** — allow the user to paste a screenshot or image into the TUI or web UI. The agent uses Claude's vision capabilities to interpret the image as part of the message. Useful for: UI bug reports, architecture diagrams, handwritten notes.

---

## Ecosystem Ideas

**Codabrus as MCP server** — already in ADR-0004, but worth emphasizing: exposing Codabrus's tools as an MCP server means any other AI assistant (Claude.ai, Cursor, etc.) can use them. This grows the ecosystem value both ways.

**Plugin registry** — a community registry of Codabrus plugins (custom tools, agent configs, skill libraries). Similar to npm but for Codabrus extensions. Each plugin is a Quicklisp-compatible ASDF system.

**Codabrus Cloud** — managed hosting for Codabrus sessions with a web UI, team collaboration (multiple users in one session), and usage analytics. Long-term SaaS opportunity.

**CI/CD integration** — run Codabrus as a step in a GitHub Actions workflow: `codabrus --prompt "fix the failing tests" --non-interactive`. Returns exit code 0 if successful, 1 if not.
