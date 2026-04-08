# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Codabrus is a hackable AI code assistant written in Common Lisp. It provides an AI agent framework with tools for reading, searching, and editing files in a project.

**Design principles:** [`docs/principles.md`](docs/principles.md)  
**Architecture:** [`docs/architecture.md`](docs/architecture.md)  
**Roadmap:** [`docs/implementation-plan.md`](docs/implementation-plan.md)  
**Ideas backlog:** [`docs/ideas.md`](docs/ideas.md)  
**ADRs:** [`docs/adr/`](docs/adr/)

All non-trivial changes must begin with an ADR in `docs/adr/NNNN-title.md`. Code follows the spec.

## Development Commands

All commands run inside a Common Lisp REPL (SBCL or CCL):

```lisp
;; Load the project
(asdf:load-system "codabrus")

;; Run all tests
(asdf:test-system "codabrus")

;; Run a single test file (Rove)
(rove:run-suite :codabrus-tests/core)

;; Try the AI agent manually
(codabrus:test-ai "your request here")
```

Dependencies are managed via Quicklisp/Ultralisp. Use `qlfile` with `qlot` to install:

```bash
qlot install
qlot exec sbcl --load codabrus.asd
```

## Architecture

The project uses ASDF package-inferred systems — each file is its own package.

**`src/vars.lisp`** — defines `*project-dir*`, the root directory the agent operates on. All tools resolve paths relative to this var.

**`src/core.lisp`** — the main entry point. Imports tools and calls `40ants-ai-agents:process` with an agent constructed from those tools and a minimal system prompt. The `test-ai` function accepts an optional previous state for multi-turn conversations.

**`src/tools/`** — each file defines one tool using the `defun-tool` macro from the `completions` library:
- `read-file.lisp` — reads file contents (max 250 lines per call), returns XML-wrapped output
- `search.lisp` — wraps `rg` (ripgrep) for pattern search across the project, capped at 2000 chars
- `edit-file.lisp` — applies unified diff patches using Unix `patch`; handles new file creation

**`src/ci.lisp`** — defines GitHub Actions workflows (linter, docs, tests) using `40ants-ci`.

**`docs/`** — documentation generated via `40ants-doc`; build with `(asdf:load-system "codabrus-docs")`.

## Key Dependencies

- **40ants-ai-agents** — provides `ai-agent`, `state`, and `process` for the agent loop
- **completions** — provides `defun-tool` macro for declaring agent tools
- **sento** — actor model for concurrent sessions (planned, see ADR-0001)
- **reblocks** — web UI (planned)
- **serapeum** — general utilities
- **uiop** — portable file I/O (used in `read-file`)
- **cl-ppcre** — regex (used in tools)

## Lessons Learned

As you work on this project, keep [`lessons-learned.md`](lessons-learned.md) up to date.
Add any non-obvious insights that would help future work: tricky CL behaviour, library quirks,
patterns that turned out to work well (or badly), and anything else that is not obvious from
reading the code. Small, concrete entries are better than long summaries.

## Tool Pattern

New tools follow this pattern in `src/tools/<name>.lisp`:

```lisp
(defun-tool my-tool ((param "description of param"))
  "Description shown to the AI"
  ...)
```

Then import the tool symbol in `src/core.lisp` and add it to the agent's tool list.
