(uiop:define-package #:codabrus/cli/resume
  (:use #:cl)
  (:import-from #:defmain
                #:defcommand)
  (:import-from #:codabrus/cli/main
                #:main
                #:run-one-shot
                #:interactive-loop
                #:prompt
                #:model
                #:output
                #:audit-log
                #:max-turns
                #:max-cost-usd)
  (:import-from #:codabrus/session-store
                #:load-session)
  (:import-from #:codabrus/session
                #:session-id))
(in-package #:codabrus/cli/resume)


(defcommand (main resume) ((session-id "Session UUID to resume."
                                       :short "s")
                           (prompt "A prompt for the agent.")
                           (model "Override the default model for this run."
                                  :short "m")
                           (max-turns "Abort after this many LLM round-trips (default: 20)."
                                      :short nil)
                           (max-cost-usd "Abort if accumulated cost in USD exceeds this threshold."
                                         :short nil))
  "Continue an existing session."
  (let ((session (load-session session-id)))
    (format *error-output* "session: ~A~%" (session-id session))
    (uiop:quit
     (if prompt
         (run-one-shot session prompt
                       :model model :output output :audit-log audit-log
                       :max-turns max-turns :max-cost-usd max-cost-usd)
         (interactive-loop session
                           :model model :output output :audit-log audit-log
                           :max-turns max-turns :max-cost-usd max-cost-usd)))))
