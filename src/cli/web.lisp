(uiop:define-package #:codabrus/cli/web
  (:use #:cl)
  (:import-from #:defmain
                #:defcommand)
  (:import-from #:codabrus/cli/main
                #:main)
  (:import-from #:40ants-slynk)
  (:import-from #:codabrus/frontend/server
                #:start))
(in-package #:codabrus/cli/web)


(defcommand (main web) ((port "Port to listen on (default: 8000)."
                              :short "p"))
  "Start Codabrus Web UI."
  (40ants-slynk:start-slynk-if-needed)
  (start :port (if port (parse-integer port) 8000))
  (loop do (sleep 10)))
