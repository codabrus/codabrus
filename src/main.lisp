(uiop:define-package #:codabrus/main
  (:use #:cl)
  (:import-from #:cl-mcp)
  (:import-from #:40ants-lisp-dev-mcp/core)
  (:import-from #:defmain
                #:defmain)
  (:import-from #:log)
  (:import-from #:40ants-slynk)
  (:import-from #:40ants-logging)
  (:import-from #:yason
                #:encode-alist
                #:with-output-to-string*
                #:*list-encoder*
                #:*symbol-key-encoder*)
  (:import-from #:str
                #:param-case)
  (:import-from #:codabrus/session
                #:make-session
                #:run-session
                #:session-response
                #:session-id
                #:session-tokens-in
                #:session-tokens-out
                #:session-total-cost-usd
                 #:compute-turn-cost
                 #:with-provider-tool-hooks)
  (:import-from #:codabrus/session-store
                #:save-session
                #:load-session)
  (:import-from #:codabrus/secrets
                #:read-token)
  (:import-from #:codabrus/vars
                #:*model*
                #:*headless-mode*
                #:*allow-execute*
                #:headless-permission-denied)
  (:import-from #:40ants-ai-agents/llm-provider
                #:*max-turns*
                #:*max-cost-usd*
                #:*cost-fn*
                #:budget-exceeded
                #:budget-exceeded-message)
  (:export #:main))
(in-package #:codabrus/main)


(defun %setup-common ()
  "Load local config and set the API key. Called in all modes."
  (let ((local-config-filename (probe-file ".local-config.lisp"))
        (current-dir (merge-pathnames (make-pathname :directory '(:relative)))))
    (cond
      (local-config-filename
       (log:info "Loading config from ~A" local-config-filename)
       (load local-config-filename))
      (t
       (log:warn "There is no .local-config.lisp file. Current-directory is ~A"
                 current-dir))))
  (setf 40ants-ai-agents/vars:*api-key*
        (or (read-token "deepseek")
            (error "No API token found for provider \"deepseek\". ~
                    Add it to ~~/.config/codabrus/secrets.json ~
                    or set DEEPSEEK_API_TOKEN env var."))))


(defun %encode-json-line (alist)
  "Encode ALIST as a JSON Lines string."
  (let ((*list-encoder* 'encode-alist)
        (*symbol-key-encoder* (lambda (sym)
                                (param-case (symbol-name sym)))))
    (with-output-to-string* ()
      (encode-alist alist))))

(defun %emit-json-line (alist)
  "Encode ALIST as a JSON object and print it as a JSON Line to stdout."
  (format t "~A~%" (%encode-json-line alist)))

(defun %write-audit-line (stream alist)
  "Encode ALIST as a JSON Line and write it to STREAM, flushing immediately."
  (format stream "~A~%" (%encode-json-line alist))
  (force-output stream))



(defmain (main) ((prompt "Run a single task and exit."
                          :short "p")
                 (session-id "Resume an existing session by its UUID."
                             :short "s")
                 (model "Override the default model for this run."
                        :short "m")
                 (non-interactive "Activate headless mode: no confirmation prompts. ~
                                   Also activated when the CI environment variable is \"true\"."
                                  :flag t)
                 (allow-execute "Allow :execute tier tools (e.g. bash) in headless mode."
                                :flag t)
                 (output "Output format: plain (default) or json (JSON Lines to stdout). In json mode, logs are written to \"codabrus.log\" by default.")
                 (log-filename "A path to a file where to write logs. If not given, then they will be written to stdout.")
                 (max-turns "Abort after this many LLM round-trips (default: 20)."
                            :short nil)
                 (max-cost-usd "Abort if accumulated cost in USD exceeds this threshold."
                               :short nil)
                 (audit-log "Write every tool invocation, result, and cost entry to this JSONL file. ~
                              Written incrementally so partial logs survive crashes."
                             :short nil)
                 &rest args)
  "Codabrus — hackable AI code assistant."

  (let ((*headless-mode* (or non-interactive
                             (string= (uiop:getenv "CI") "true")))
        (*allow-execute* allow-execute)
        (json-p (string= (or output "plain") "json")))
    (40ants-logging:setup-for-backend :level :debug
                                      :filename (cond
                                                  (log-filename
                                                   (pathname log-filename))
                                                  (json-p
                                                    #P"codabrus.log")))
    (%setup-common)
    
    (cond
       (prompt
        ;; CLI mode: run one task and exit
        (let* ((session (if session-id
                          (load-session session-id)
                          (let ((project-dir (if args
                                               (pathname (first args))
                                               (uiop:getcwd))))
                            (make-session project-dir))))
               (audit-stream (when audit-log
                               (open (pathname audit-log)
                                     :direction :output
                                     :if-exists :supersede
                                     :if-does-not-exist :create))))
          (format *error-output* "session: ~A~%" (session-id session))
         (unwind-protect
              (handler-case
                  (let* ((*model* (or model *model*))
                         (*max-turns* (if max-turns (parse-integer max-turns) 20))
                         (*max-cost-usd* (when max-cost-usd
                                           (let ((*read-eval* nil))
                                             (coerce (read-from-string max-cost-usd) 'double-float))))
                         (*cost-fn* #'compute-turn-cost)
                         (result (run-session session prompt
                                               :tool-call-hook
                                               (when (or json-p audit-stream)
                                                 (lambda (call-id fn-name raw-args)
                                                   (declare (ignore call-id))
                                                   (log:debug "Tool ~A is called" fn-name)
                                                   (let ((call-entry `((:event . "tool-call")
                                                                       (:tool . ,fn-name)
                                                                       (:args . ,raw-args))))
                                                     (when json-p
                                                       (%emit-json-line call-entry))
                                                     (when audit-stream
                                                       (%write-audit-line audit-stream call-entry)))))
                                               :tool-result-hook
                                               (when (or json-p audit-stream)
                                                 (lambda (call-id result)
                                                   (declare (ignore call-id))
                                                   (let ((result-entry `((:event . "tool-result")
                                                                         (:tool . "unknown")
                                                                         (:result . ,result))))
                                                     (when json-p
                                                       (%emit-json-line result-entry))
                                                     (when audit-stream
                                                       (%write-audit-line audit-stream result-entry))))))))
                     (save-session result)
                     ;; Text output
                    (let ((response (session-response result)))
                      (when response
                        (if json-p
                          (%emit-json-line `((:event . "text") (:content . ,response)))
                          (format t "~A~%" response))))
                    ;; Cost summary → stderr in all modes
                    (format *error-output*
                            "[tokens: ~A in / ~A out | cost: $~,3F]~%"
                            (session-tokens-in result)
                            (session-tokens-out result)
                            (session-total-cost-usd result))
                    ;; JSON-only structured events
                    (when json-p
                      (%emit-json-line `((:event . "cost")
                                          (:tokens-in  . ,(session-tokens-in result))
                                          (:tokens-out . ,(session-tokens-out result))
                                          (:cost-usd   . ,(session-total-cost-usd result))))
                      (%emit-json-line '((:event . "finish") (:status . "ok"))))
                    ;; Audit log cost + finish
                    (when audit-stream
                      (%write-audit-line audit-stream `((:event . "cost")
                                                         (:tokens-in  . ,(session-tokens-in result))
                                                         (:tokens-out . ,(session-tokens-out result))
                                                         (:cost-usd   . ,(session-total-cost-usd result))))
                      (%write-audit-line audit-stream '((:event . "finish") (:status . "ok"))))
                    (uiop:quit 0))
                (headless-permission-denied (c)
                  (format *error-output* "Permission denied: ~A~%" c)
                  (when audit-stream
                    (%write-audit-line audit-stream `((:event . "finish")
                                                       (:status . "permission-denied")
                                                       (:message . ,(format nil "~A" c)))))
                  (uiop:quit 2))
                (budget-exceeded (c)
                  (format *error-output* "~A~%" c)
                  (when json-p
                    (%emit-json-line `((:event . "finish")
                                       (:status . "budget-exceeded")
                                       (:message . ,(budget-exceeded-message c)))))
                  (when audit-stream
                    (%write-audit-line audit-stream `((:event . "finish")
                                                       (:status . "budget-exceeded")
                                                       (:message . ,(budget-exceeded-message c)))))
                  (uiop:quit 1))
                (error (e)
                  (format *error-output* "Error: ~A~%" e)
                  (when json-p
                    (%emit-json-line `((:event . "finish")
                                       (:status . "error")
                                       (:message . ,(format nil "~A" e)))))
                  (when audit-stream
                    (%write-audit-line audit-stream `((:event . "finish")
                                                       (:status . "error")
                                                       (:message . ,(format nil "~A" e)))))
                  (uiop:quit 1)))
           (when audit-stream
             (close audit-stream)))))
      (t
       ;; Server mode: start Slynk and MCP, then loop
       (40ants-slynk:start-slynk-if-needed)
       (when (uiop:getenv "MCP_PORT")
         (40ants-lisp-dev-mcp/core:start-server :port (parse-integer (uiop:getenv "MCP_PORT")))
         ;; (cl-mcp:start-http-server :port (1+ (parse-integer (uiop:getenv "MCP_PORT"))))
         )
       (loop do (sleep 10))))))
