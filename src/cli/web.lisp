(uiop:define-package #:codabrus/cli/web
  (:use #:cl)
  (:import-from #:defmain
                #:defcommand)
  (:import-from #:codabrus/cli/main
                #:main)
  (:import-from #:40ants-slynk)
  (:import-from #:40ants-lisp-dev-mcp/core)
  (:import-from #:codabrus/frontend/server
                #:start))
(in-package #:codabrus/cli/web)


(defcommand (main web) ((port "Port to listen on (default: 8000)."
                              :short "p"))
  "Start Codabrus Web UI."
  (40ants-slynk:start-slynk-if-needed)
  (when (uiop:getenv "MCP_PORT")
    (40ants-lisp-dev-mcp/core:start-server
     :port (parse-integer (uiop:getenv "MCP_PORT"))))
  (start :port (if port (parse-integer port) 8000))
  (loop do (sleep 10)))
