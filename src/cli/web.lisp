(uiop:define-package #:codabrus/cli/web
  (:use #:cl)
  (:import-from #:defmain
                #:defcommand)
  (:import-from #:codabrus/cli/main
                #:main)
  (:import-from #:codabrus/frontend/server
                #:start))
(in-package #:codabrus/cli/web)


(defcommand (main web) ((port "Port to listen on (default: 8000)."
                              :short "p"))
  "Start Codabrus Web UI."
  (start :port (if port (parse-integer port) 8000))
  (loop do (sleep 10)))
