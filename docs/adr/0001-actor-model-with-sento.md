# ADR-0001: Use Sento Actor Model for Session Concurrency

**Status:** Proposed  
**Date:** 2026-04-08

## Context

Codabrus needs to support multiple concurrent sessions, each involving a long-running agent loop (LLM calls, tool execution). Users may interact via a TUI, web UI, or IDE client simultaneously. Tool calls within a session can in principle run in parallel (e.g., reading two files at once).

The naive approach — a synchronous call to `40ants-ai-agents:process` inside a single thread — works for the current single-session REPL prototype but cannot support:
- Multiple simultaneous user sessions
- Streaming output to the UI while tools execute
- Parallel tool execution
- Subagent delegation
- Remote execution of tools or agents

We need a concurrency model.

## Options Considered

**Option A: BORDEAUX-THREADS + locks**  
Manual thread management with mutexes for shared state. Low-level, error-prone, hard to compose, no built-in message passing.

**Option B: LPARALLEL (futures/promises)**  
Good for data-parallel pipelines but not for stateful actors with mailboxes. Doesn't model the session-as-serialized-queue pattern well.

**Option C: Sento actor model**  
Sento provides Erlang-style actors (actorsystem, actors, ask!/tell!). Each actor has a mailbox; messages are processed one at a time (serialized). Actors can be on remote nodes via a transport layer. This maps directly to our needs: one session = one actor, one LLM call = one task dispatched to a worker actor.

## Decision

Use **Sento** as the concurrency substrate.

- Each session is a Sento actor (`session-actor`)
- The Session Manager is a top-level Sento actor
- Long-running operations (LLM calls) are dispatched as async tasks via Sento's `async-ask`
- The event bus is implemented via Sento's pub/sub facilities
- Subagents are child actors spawned by a session actor

The agent core loop itself (process-step) is a plain Lisp function — not an actor — called synchronously within the session actor's message handler. This keeps the loop logic pure and testable without Sento.

## Consequences

**Good:**
- Session state is never shared between threads; no locks needed for session data
- Clean lifecycle (actor creation/destruction maps to session open/close)
- Message-passing interface makes multiple UIs trivial: any number of subscribers on the event bus
- Remote execution is an architectural feature, not a retrofit
- Actors are inspectable from the REPL via Sento's introspection

**Neutral:**
- Sento is an additional dependency; it is available via Quicklisp/Ultralisp
- All mutable session state must go through the actor; reading state requires `ask!`

**Risk:**
- Sento is less mature than Java/Erlang actor libraries; we may hit edge cases
- Mitigation: keep the actor surface small; the agent loop is sync and pure, so actor failures are session-scoped
