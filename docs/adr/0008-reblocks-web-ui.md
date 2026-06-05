# ADR-0008: Web UI with Reblocks

## Status

Proposed

## Context

Codabrus currently operates as a CLI tool. A web UI would make it more accessible and provide a foundation for future features like session browsing, configuration, and real-time agent monitoring.

## Decision

We will use the **Reblocks** framework to build a web UI, placed in `src/frontend/`. This follows the same pattern used in other projects in the same ecosystem (e.g., staticbot).

Reblocks is chosen because:
- It is a Common Lisp web framework with server-side widget rendering
- It integrates well with the 40ants ecosystem already used in the project
- It supports Tailwind CSS themes via `reblocks-ui2`
- It uses a familiar `defwidget`/`defapp`/`defroutes` pattern

The initial implementation is a single page showing the "Codabrus" title, with a `web` CLI subcommand to start the server.

## Consequences

- Adds `reblocks` and `reblocks-ui2` as runtime dependencies
- The `codabrus web` command starts an HTTP server (default: Hunchentoot on port 8000)
- The `src/frontend/` directory will grow as more pages are added
