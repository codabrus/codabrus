# Plan: 4.1 Session Actor

## Context

Current state: `run-session` in `src/session.lisp` is a synchronous function called directly from REPL (`src/repl.lisp`) and CLI (`src/cli/main.lisp`). Session is immutable — `run-session` returns a new instance. No concurrency, no events.

Goal: wrap session in a Sento actor to:
1. Serialize access to session state (mailbox)
2. Publish events (tool-call, tool-result, text, cost, finish) via event-emitter
3. Support future UIs (TUI, Web, ACP) through event subscription

## What already exists

- **Sento** available via Quicklisp/Ultralisp (`sento` system)
- Sento API: `make-actor-system`, `actor-of`, `ask-s`/`ask`/`tell`, `reply`, EventStream (`subscribe`/`publish`), `ac:shutdown`
- Session — immutable `defclass` with `make-session`/`run-session` (Phase 1)
- Persistence — `save-session`/`load-session` (Phase 3)
- CLI — `run-one-shot` and `interactive-loop` call `run-session` directly
- **event-emitter** — already a dependency, used in `with-provider-tool-hooks`

## Key decision from ADR-0001

> The agent core loop itself (process-step) is a plain Lisp function — not an actor — called synchronously within the session actor's message handler. This keeps the loop logic pure and testable without Sento.

## Decisions

1. **Event bus:** Sento EventStream is global and shared by all actors — not suitable for per-session event management. Use `event-emitter` library (already a dependency) for per-session event publishing. Subscribers (REPL, CLI, future TUI/Web) register via `event-emitter:on`.
2. **REPL:** no backward compatibility — REPL always uses actor. Actor-system is created at `setup`.

## Event architecture

```
[Session Actor]
    | (receive :run prompt)
    | calls run-session with hooks
    |---> event-emitter:emit :tool-call event-emitter-instance ...
    |---> event-emitter:emit :tool-result ...
    |---> event-emitter:emit :text ...
    |---> event-emitter:emit :cost ...
    +---> event-emitter:emit :finish ...
```

Session actor holds an `event-emitter` instance. Subscribers register via `event-emitter:on`.

## Implementation steps

### 1. `src/actors/actor-system.lisp` (new)

Package: `#:codabrus/actors/actor-system`

```lisp
(defvar *actor-system* nil)

(defun start-actor-system (&optional config)
  (setf *actor-system* (asys:make-actor-system config)))

(defun stop-actor-system ()
  (when *actor-system*
    (ac:shutdown *actor-system*)
    (setf *actor-system* nil)))
```

### 2. `src/actors/session-actor.lisp` (new) — **core of this phase**

Package: `#:codabrus/actors/session-actor`

```lisp
(defun make-session-actor (actor-context session &key event-emitter)
  (actor-of actor-context
    :name (format nil "session-~A" (session-id session))
    :receive
    (lambda (msg)
      (destructuring-bind (type &rest payload) (ensure-list msg)
        (case type
          (:run
           ;; payload: (prompt)
           ;; 1. emit :run-started
           ;; 2. run-session with hooks that:
           ;;    - tool-call-hook -> emit :tool-call
           ;;    - tool-result-hook -> emit :tool-result
           ;; 3. setf *state* result
           ;; 4. save-session result
           ;; 5. emit :text (response), :cost, :finish
           ;; 6. reply result (for ask-s)
           ...)
          (:get-state
           ;; reply *state*
           ...)
          (:abort
           ;; set abort flag (future, when agent loop supports it)
           ...))))))
```

Internal actor state: current `session` instance (via Sento `*state*`) + `event-emitter`.

Exports:
- `make-session-actor`
- `session-actor-event-emitter` (getter for subscription)
- `send-prompt` (wrapper over `ask-s`)
- `get-current-session` (wrapper over `ask-s :get-state`)

### 3. `codabrus.asd` — add sento dependency

Add `"sento"` to `:depends-on`.

### 4. `src/repl.lisp` — rewrite through actor

```
setup:
  (start-actor-system)
  (let ((session (make-session project-dir :model model)))
    (setf *session-actor* (make-session-actor *actor-system* session)))
  (subscribe to event-emitter for terminal output)

chat:
  (ask-s *session-actor* `(:run ,message))
  ;; event-emitter callback already printed the response
```

### 5. `src/cli/main.lisp` — rewrite through actor

`run-one-shot` / `interactive-loop`:
1. Create actor-system + session-actor
2. Subscribe to event-emitter for JSON/audit/plain output
3. Call `ask-s session-actor '(:run ,prompt)`
4. On exit — `stop-actor-system`

### 6. `src/cli/new.lisp` — create session actor

`codabrus new` creates actor-system + session + session-actor.

### 7. `src/cli/resume.lisp` — load session + create actor

`codabrus resume` loads session from store + creates session-actor.

### 8. `t/session-actor.lisp` (new)

Package: `#:codabrus-tests/session-actor`

Tests:
1. `make-session-actor` creates actor in test actor-system
2. `(:get-state)` returns initial session
3. `(:run prompt)` — integration test with mock/real LLM:
   - Actor returns updated session via `ask-s`
   - Events are published (verify via event-emitter callback)
4. Two consecutive `(:run ...)` — second continues history
5. Error in `run-session` — actor doesn't crash, returns error
6. `ac:shutdown` cleans up resources

All tests wrapped in `unwind-protect` with `ac:shutdown`.

## Implementation order

| # | File | Description | Complexity |
|---|------|-------------|------------|
| 1 | `src/actors/actor-system.lisp` | Wrapper for Sento actor-system | Low |
| 2 | `src/actors/session-actor.lisp` | Session actor with `:run`, `:get-state`, event-emitter | **High** |
| 3 | `codabrus.asd` | Add sento dependency | Trivial |
| 4 | `src/repl.lisp` | Rewrite `chat` through actor | Medium |
| 5 | `src/cli/main.lisp` | Rewrite `run-one-shot` / `interactive-loop` through actor | Medium |
| 6 | `src/cli/new.lisp` | Create session actor on `codabrus new` | Low |
| 7 | `src/cli/resume.lisp` | Load session + create actor on `codabrus resume` | Low |
| 8 | `t/session-actor.lisp` | Tests for actor | Medium |
