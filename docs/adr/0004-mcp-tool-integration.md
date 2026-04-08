# ADR-0004: MCP Protocol for Tool Ecosystem Integration

**Status:** Proposed  
**Date:** 2026-04-08

## Context

Codabrus needs tools beyond file editing: GitHub issues, databases, web search, documentation lookup, CI status, and more. Building each of these natively would be enormous work.

The Model Context Protocol (MCP) is an open standard that defines how AI assistants discover and call tools provided by external servers. There is already a significant ecosystem of MCP servers (hundreds of ready-made integrations). Codabrus's own vendored `libs/lisp-dev-mcp/` is an MCP server.

## Decision

Implement an **MCP client** in Codabrus that:

1. Reads MCP server configurations from `~/.codabrus/config.lisp` (global) and `<project>/.codabrus/mcp.lisp` (project-level)
2. At session start, connects to configured MCP servers and fetches their tool manifests
3. Dynamically registers discovered tools in the session's tool registry
4. Routes `tool-call-part` events for MCP tools through the MCP client transport (stdio or HTTP/SSE)
5. Wraps results as `tool-result-part` events

MCP tools participate in the same permission system as built-in tools. A tool from an MCP server that executes shell commands gets the same `:execute` permission tier as the built-in `bash` tool.

Conversely, Codabrus itself **exposes** an MCP server endpoint so IDE plugins and other agents can call Codabrus tools (read-file, search, edit-file) without a full Codabrus session.

Configuration example:
```lisp
;; <project>/.codabrus/mcp.lisp
(:mcp-servers
  (:github   :command "mcp-github"   :args ())
  (:postgres :command "mcp-postgres" :args ("postgres://localhost/mydb"))
  (:lisp-dev :command "qlot" :args ("exec" "sbcl" "--load" "libs/lisp-dev-mcp/server.lisp")))
```

## Consequences

**Good:**
- Immediate access to a large ecosystem without building integrations from scratch
- Community-maintained servers benefit from updates without changes to Codabrus
- Composable: different projects enable different MCP servers
- Codabrus as MCP server enables IDE integration without ACP

**Neutral:**
- MCP is a relatively new standard; the Common Lisp client library may need to be written or adapted from an existing implementation
- We already have `libs/lisp-dev-mcp/` which can serve as reference for the client

**Risk:**
- MCP servers are external processes; failures must not crash the session
- Mitigation: MCP tool calls are wrapped in condition handlers; a failed MCP call returns an error `tool-result-part`
