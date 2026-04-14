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
  "
TODO: Write a library description. Put some examples here.
")


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
""")


(defautodoc @api (:system "codabrus"))
