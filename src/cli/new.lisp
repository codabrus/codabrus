(uiop:define-package #:codabrus/cli/new
  (:use #:cl)
  (:import-from #:defmain
                #:defcommand)
  (:import-from #:codabrus/cli/main
                #:main
                #:run-one-shot
                #:interactive-loop
                #:output
                #:audit-log)
  (:import-from #:codabrus/session
                #:make-session
                #:session-id))
(in-package #:codabrus/cli/new)


(defcommand (main new) ((prompt "A prompt for the agent.")
                        (project-dir "A directory to work in. If not given, then current directory will be used."
                                     :short nil)
                        (model "Override the default model for this run."
                               :short "m")
                        (max-turns "Abort after this many LLM round-trips (default: 20)."
                                   :short nil)
                        (max-cost-usd "Abort if accumulated cost in USD exceeds this threshold."
                                      :short nil))
  "Start a new session."
  (let* ((project-dir (or (when project-dir
                            (or (probe-file project-dir)
                                (format *error-output* "Directory ~A not found." project-dir)
                                (uiop:quit 1)))
                          (uiop:getcwd)))
         (session (make-session project-dir)))
    (format *error-output* "Session: ~A~%" (session-id session))
    (format *error-output* "Model: ~A~%" model)
    (format *error-output* "Max turns: ~A~%" max-turns)
    (format *error-output* "Max cost (USD): ~A~%" max-cost-usd)
    
    (uiop:quit
     (cond
       (prompt
        (run-one-shot session prompt
                      :model model
                      :output output
                      :audit-log audit-log
                      :max-turns max-turns
                      :max-cost-usd max-cost-usd))
       (t
        (interactive-loop session
                          :model model
                          :output output
                          :audit-log audit-log
                          :max-turns max-turns
                          :max-cost-usd max-cost-usd))))))
