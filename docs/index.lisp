(uiop:define-package #:codabrus-docs/index
  (:use #:cl)
  (:import-from #:pythonic-string-reader
                #:pythonic-string-syntax)
  #+quicklisp
  (:import-from #:quicklisp)
  (:import-from #:named-readtables
                #:in-readtable)
  (:import-from #:40ants-doc
                #:defsection
                #:defsection-copy)
  (:import-from #:codabrus-docs/changelog
                #:@changelog)
  (:import-from #:docs-config
                #:docs-config)
  (:import-from #:40ants-doc/autodoc
                #:defautodoc)
  (:export #:@index
           #:@readme
           #:@changelog))
(in-package #:codabrus-docs/index)

(in-readtable pythonic-string-syntax)


(defmethod docs-config ((system (eql (asdf:find-system "codabrus-docs"))))
  ;; 40ANTS-DOC-THEME-40ANTS system will bring
  ;; as dependency a full 40ANTS-DOC but we don't want
  ;; unnecessary dependencies here:
  #+quicklisp
  (ql:quickload "40ants-doc-theme-40ants")
  #-quicklisp
  (asdf:load-system "40ants-doc-theme-40ants")
  
  (list :theme
        (find-symbol "40ANTS-THEME"
                     (find-package "40ANTS-DOC-THEME-40ANTS")))
  )


(defsection @index (:title "codabrus - Hackable AI Code Assistant written in Common Lisp."
                    :ignore-words ("JSON"
                                   "HTTP"
                                   "TODO"
                                   "Unlicense"
                                   "REPL"
                                   "ASDF:PACKAGE-INFERRED-SYSTEM"
                                   "ASDF"
                                   "40A"
                                   "API"
                                   "URL"
                                   "URI"
                                   "RPC"
                                   "GIT"))
  (codabrus system)
  "
[![](https://github-actions.40ants.com///matrix.svg?only=ci.run-tests)](https://github.org/codabrus/codabrus/actions)

![Quicklisp](http://quickdocs.org/badge/codabrus.svg)
"
  (@installation section)
  (@usage section)
  (@repl section)
  (@logging-and-audit section)
  (@api section))


(defsection-copy @readme @index)


(defsection @installation (:title "Installation")
  """
You can install this library from Quicklisp, but you want to receive updates quickly, then install it from Ultralisp.org:

```
(ql-dist:install-dist "http://dist.ultralisp.org/"
                      :prompt nil)
(ql:quickload :codabrus)
```
""")


(defsection @usage (:title "Usage")
  """
## One-shot mode

Run a single task and exit:

```
codabrus --prompt "fix the failing tests" /path/to/project
```

The agent reads files, searches the codebase, edits files, and runs shell
commands to complete the task. A session ID is printed to stderr so you can
continue the conversation later.

## Multi-turn sessions

Each run creates a session (or resumes an existing one). Sessions are stored as
Markdown files in `~/.cache/codabrus/sessions/<uuid>.md` — you can inspect them
with any text editor.

### Resume a session

```
# First run — a new session is created
codabrus --prompt "add error handling to src/core.lisp" .
# stderr: session: f47ac10b-58cc-4372-a567-0e02b2c3d479

# Continue in the same session
codabrus --session-id f47ac10b-58cc-4372-a567-0e02b2c3d479 \
         --prompt "now run the tests"
```

### Session files

Each session file has a YAML-like frontmatter with metadata and a Markdown body
with the full conversation:

```markdown
---
id: "f47ac10b-58cc-4372-a567-0e02b2c3d479"
project-dir: "/Users/art/projects/lisp/codabrus"
model: "deepseek-chat"
tokens-in: 1234
tokens-out: 567
total-cost-usd: 0.003
created-at: "2026-04-15T10:30:00"
updated-at: "2026-04-15T10:35:00"
---

## User

fix the failing tests

## Assistant

I'll look at the test failures and fix them...
```

Sessions are saved automatically after each run. No data is lost if the process
crashes — everything written up to the last completed turn is persisted.
""")


(defsection @repl (:title "REPL Testing")
  """
The `codabrus/repl` package provides convenience functions for interactive
testing from the Lisp REPL.

## Setup

```
(asdf:load-system "codabrus")

;; Initialize API key, model, and session
(codabrus/repl:setup)
;; => Ready. Model=deepseek-chat Dir=/path/to/project Session=uuid

;; With options
(codabrus/repl:setup :model "claude-3-opus"
                      :project-dir #p"/path/to/project"
                      :max-turns 5
                      :max-cost-usd 0.10d0)
```

`setup` reads the API key from secrets by default. Pass `:api-key` to
override.

## Sending messages

```
;; Send a message, print response and cost, update *session*
(codabrus/repl:chat "List files in current directory")

;; Continue the conversation — same session
(codabrus/repl:chat "Now fix the first bug you find")

;; With verbose tool logging
(codabrus/repl:chat "Search for TODO comments" :verbose t)
;;   [CALL] search-file "TODO"
;;   [RESULT] src/foo.lisp:42: TODO fix this ...
;; I found TODO comments in the following files...

;; Return just the response text (no printing)
;; (let ((text (codabrus/repl:chat* "What is this project?")))
;;   (length text))
```

## Inspecting state

```
;; Current session object
codabrus/repl:*session*

;; Last response text
(codabrus/repl:last-response)

;; Print full conversation history
(codabrus/repl:history)

;; Print token usage and cost
(codabrus/repl:cost codabrus/repl:*session*)

;; Print history of any session
(codabrus/repl:show codabrus/repl:*session*)
```

## Switching providers

```
;; Gemini
(codabrus/repl:setup :model "gemini-2.0-flash" :api-key "...")

;; Claude
(codabrus/repl:setup :model "claude-3-opus" :api-key "...")

;; Ollama (local, no key needed)
(codabrus/repl:setup :model "llama3.2" :api-key "unused")
```

## Quick reference

| Function | Description |
|---|---|
| `setup &key project-dir model api-key max-turns max-cost-usd` | Initialize session and API key |
| `chat message &key verbose` | Send message, print response, return session |
| `chat* message` | Send message, return response text only |
| `show session` | Print full conversation history |
| `cost session` | Print token usage and cost |
| `history` | Print current session history |
| `last-response` | Return last assistant response text |
| `*session*` | Current session object (updated by `chat`) |
""")


(defsection @logging-and-audit (:title "Logging & Audit")
  """
Codabrus provides two independent mechanisms for capturing structured run data.

## Structured stdout: `--output json`

```
codabrus --output json --prompt "..."
```

Switches the process output to [JSON Lines](https://jsonlines.org/) format on stdout.
Each event is a self-contained JSON object on its own line:

| Event | When emitted |
|---|---|
| `tool-call` | Before a tool is executed (includes tool name and arguments) |
| `tool-result` | After a tool returns (includes the result) |
| `text` | The final assistant response |
| `cost` | Token counts and USD cost for the run |
| `finish` | End of run with status (`ok`, `budget-exceeded`, `error`) |

In this mode, logs are redirected to `codabrus.log` (or `--log-filename`) so that
structured events are the only thing on stdout. Useful for piping:

```
codabrus --output json --prompt "..." | jq 'select(.event == "cost")'
```

## Persistent audit log: `--audit-log`

```
codabrus --audit-log /tmp/run.jsonl --prompt "..."
```

Writes the same JSON Lines events to a file without affecting stdout.
Each line is flushed immediately, so the log survives crashes mid-run.
Suitable for CI artefacts, billing reconciliation, and post-run debugging.

Can be combined with `--output json` or used with the default plain output:

```
# Machine-readable stdout AND a persistent audit file
codabrus --output json --audit-log /var/log/codabrus/run.jsonl --prompt "..."

# Human-readable terminal output AND a persistent audit file
codabrus --audit-log /tmp/run.jsonl --prompt "..."
```

The finish event always carries a `status` field, so failed runs can be
identified without parsing the entire log:

```bash
jq 'select(.event == "finish")' /tmp/run.jsonl
# {"event":"finish","status":"budget-exceeded","message":"..."}
```

## GitHub Actions example

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
""")


(defautodoc @api (:system "codabrus"))
