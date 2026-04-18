(uiop:define-package #:codabrus/cli/main
  (:use #:cl)
  (:import-from #:cl-mcp)
  (:import-from #:40ants-lisp-dev-mcp/core)
  (:import-from #:defmain
                #:defmain
                #:defcommand)
  (:import-from #:net.didierverna.clon
                #:getopt)
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
                #:load-session
                #:list-sessions)
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
  (:export #:main
           #:run-cli))
(in-package #:codabrus/cli/main)


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


(defun json-output-p (output)
  (string= (or output "plain") "json"))


(defun emit-json-line (alist)
  (let ((*list-encoder* 'encode-alist)
        (*symbol-key-encoder* (lambda (sym)
                                (param-case (symbol-name sym)))))
    (format t "~A~%" (with-output-to-string* ()
                        (encode-alist alist)))))


(defun write-audit-line (stream alist)
  (let ((*list-encoder* 'encode-alist)
        (*symbol-key-encoder* (lambda (sym)
                                (param-case (symbol-name sym)))))
    (format stream "~A~%" (with-output-to-string* ()
                            (encode-alist alist)))
    (force-output stream)))


(defun open-audit-stream (audit-log)
  (when audit-log
    (open (pathname audit-log)
          :direction :output
          :if-exists :supersede
          :if-does-not-exist :create)))


(defun %make-hooks (json-p audit-stream)
  (values
   (when (or json-p audit-stream)
     (lambda (call-id fn-name raw-args)
       (declare (ignore call-id))
       (log:debug "Tool ~A is called" fn-name)
       (let ((entry `((:event . "tool-call")
                      (:tool . ,fn-name)
                      (:args . ,raw-args))))
         (when json-p
           (emit-json-line entry))
         (when audit-stream
           (write-audit-line audit-stream entry)))))
   (when (or json-p audit-stream)
     (lambda (call-id result)
       (declare (ignore call-id))
       (let ((entry `((:event . "tool-result")
                      (:tool . "unknown")
                      (:result . ,result))))
         (when json-p
           (emit-json-line entry))
         (when audit-stream
           (write-audit-line audit-stream entry)))))))


(defun run-one-shot (session prompt
                     &key model output audit-log
                       max-turns max-cost-usd)
  "Run a single prompt against SESSION, print output, handle errors. Returns exit code."
  (let* ((json-p (json-output-p output))
         (audit-stream (open-audit-stream audit-log))
         (effective-model (or model *model*)))
    (unwind-protect
         (handler-case
             (let* ((*model* effective-model)
                    (*max-turns* (if max-turns (parse-integer max-turns) 20))
                    (*max-cost-usd* (when max-cost-usd
                                      (let ((*read-eval* nil))
                                        (coerce (read-from-string max-cost-usd) 'double-float))))
                    (*cost-fn* #'compute-turn-cost)
                    (call-hook nil)
                    (result-hook nil))
               (setf (values call-hook result-hook)
                     (%make-hooks json-p audit-stream))
               (let ((result (run-session session prompt
                                          :tool-call-hook call-hook
                                          :tool-result-hook result-hook)))
                 (save-session result)
                 (let ((response (session-response result)))
                   (when response
                     (if json-p
                         (emit-json-line `((:event . "text") (:content . ,response)))
                         (format t "~A~%" response))))
                 (format *error-output*
                         "[tokens: ~A in / ~A out | cost: $~,3F]~%"
                         (session-tokens-in result)
                         (session-tokens-out result)
                         (session-total-cost-usd result))
                 (when json-p
                   (emit-json-line `((:event . "cost")
                                     (:tokens-in  . ,(session-tokens-in result))
                                     (:tokens-out . ,(session-tokens-out result))
                                     (:cost-usd   . ,(session-total-cost-usd result))))
                   (emit-json-line '((:event . "finish") (:status . "ok"))))
                 (when audit-stream
                   (write-audit-line audit-stream `((:event . "cost")
                                                     (:tokens-in  . ,(session-tokens-in result))
                                                     (:tokens-out . ,(session-tokens-out result))
                                                     (:cost-usd   . ,(session-total-cost-usd result))))
                   (write-audit-line audit-stream '((:event . "finish") (:status . "ok"))))
                 0))
           (headless-permission-denied (c)
             (format *error-output* "Permission denied: ~A~%" c)
             (when audit-stream
               (write-audit-line audit-stream `((:event . "finish")
                                                 (:status . "permission-denied")
                                                 (:message . ,(format nil "~A" c)))))
             2)
           (budget-exceeded (c)
             (format *error-output* "~A~%" c)
             (when json-p
               (emit-json-line `((:event . "finish")
                                  (:status . "budget-exceeded")
                                  (:message . ,(budget-exceeded-message c)))))
             (when audit-stream
               (write-audit-line audit-stream `((:event . "finish")
                                                (:status . "budget-exceeded")
                                                (:message . ,(budget-exceeded-message c)))))
             1)
           (error (e)
             (format *error-output* "Error: ~A~%" e)
             (when json-p
               (emit-json-line `((:event . "finish")
                                  (:status . "error")
                                  (:message . ,(format nil "~A" e)))))
             (when audit-stream
               (write-audit-line audit-stream `((:event . "finish")
                                                (:status . "error")
                                                (:message . ,(format nil "~A" e)))))
             1))
      (when audit-stream
        (close audit-stream)))))


(defun interactive-loop (session
                         &key model output audit-log
                           max-turns max-cost-usd)
  "Read prompts from stdin in a loop, run agent, save session. Returns exit code."
  (let* ((json-p (json-output-p output))
         (audit-stream (open-audit-stream audit-log))
         (effective-model (or model *model*))
         (current-session session))
    (unwind-protect
         (loop
           (format t "~&> ")
           (finish-output t)
           (let ((line (read-line *standard-input* nil nil)))
             (unless line
               (return 0))
             (when (string= line "")
               (next-iteration))
             (handler-case
                 (let* ((*model* effective-model)
                         (*max-turns* (if max-turns (parse-integer max-turns) 20))
                        (*max-cost-usd* (when max-cost-usd
                                          (let ((*read-eval* nil))
                                            (coerce (read-from-string max-cost-usd) 'double-float))))
                        (*cost-fn* #'compute-turn-cost)
                        (call-hook nil)
                        (result-hook nil))
                   (setf (values call-hook result-hook)
                         (%make-hooks json-p audit-stream))
                   (let ((result (run-session current-session line
                                              :tool-call-hook call-hook
                                              :tool-result-hook result-hook)))
                     (save-session result)
                     (let ((response (session-response result)))
                       (when response
                         (if json-p
                             (emit-json-line `((:event . "text") (:content . ,response)))
                             (format t "~A~%" response))))
                     (format *error-output*
                             "[tokens: ~A in / ~A out | cost: $~,3F]~%"
                             (session-tokens-in result)
                             (session-tokens-out result)
                             (session-total-cost-usd result))
                     (setf current-session result)))
               (headless-permission-denied (c)
                 (format *error-output* "Permission denied: ~A~%" c)
                 (uiop:quit 2))
               (budget-exceeded (c)
                 (format *error-output* "~A~%" c)
                 (uiop:quit 1))
               (error (e)
                 (format *error-output* "Error: ~A~%" e)
                 (uiop:quit 1)))))
      (when audit-stream
        (close audit-stream)))))


(defmain (main) ((non-interactive "Activate headless mode: no confirmation prompts. ~
                                   Also activated when the CI environment variable is \"true\"."
                                  :flag t)
                 (allow-execute "Allow :execute tier tools (e.g. bash) in headless mode."
                                :flag t)
                 (output "Output format: plain (default) or json (JSON Lines to stdout). ~
                          In json mode, logs are written to \"codabrus.log\" by default.")
                 (log-filename "A path to a file where to write logs. If not given, then they will be written to stdout.")
                 (audit-log "Write every tool invocation, result, and cost entry to this JSONL file. ~
                              Written incrementally so partial logs survive crashes."
                            :short nil)
                 &subcommand)
  "Codabrus — hackable AI code assistant."

  (let ((*headless-mode* (or non-interactive
                             (string= (uiop:getenv "CI") "true")))
        (*allow-execute* allow-execute)
        (json-p (json-output-p output)))
    (40ants-logging:setup-for-backend :level :debug
                                      :filename (cond
                                                  (log-filename
                                                   (pathname log-filename))
                                                  (json-p
                                                   #P"codabrus.log")))
    (%setup-common)
    (defmain:subcommand)))
