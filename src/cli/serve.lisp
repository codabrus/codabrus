(uiop:define-package #:codabrus/cli/serve
  (:use #:cl)
  (:import-from #:defmain
                #:defcommand)
  (:import-from #:codabrus/cli/main
                #:main)
  (:import-from #:cl-mcp)
  (:import-from #:40ants-lisp-dev-mcp/core)
  (:import-from #:40ants-slynk))
(in-package #:codabrus/cli/serve)


(defcommand (main serve) ()
  "Start Slynk and MCP server, then loop forever."
  (40ants-slynk:start-slynk-if-needed)
  (when (uiop:getenv "MCP_PORT")
    (40ants-lisp-dev-mcp/core:start-server
     :port (parse-integer (uiop:getenv "MCP_PORT"))))
  (loop do (sleep 10)))
