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
                #:session-tokens-in
                #:session-tokens-out
                #:session-total-cost-usd)
  (:import-from #:codabrus/secrets
                #:read-token)
  (:import-from #:codabrus/vars
                #:*model*
                #:*headless-mode*
                #:*allow-execute*
                #:headless-permission-denied)
  (:import-from #:log4cl-extras/error
                #:with-log-unhandled)
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


(defun %emit-json-line (alist)
  "Encode ALIST as a JSON object and print it as a JSON Line to stdout."
  (let ((*list-encoder* 'encode-alist)
        (*symbol-key-encoder* (lambda (sym)
                                (param-case (symbol-name sym)))))
    (format t "~A~%" (with-output-to-string* ()
                       (encode-alist alist)))))


(defmain (main) ((prompt "Run a single task and exit."
                          :short "p")
                 (model "Override the default model for this run."
                        :short "m")
                 (non-interactive "Activate headless mode: no confirmation prompts. ~
                                   Also activated when the CI environment variable is \"true\"."
                                  :flag t)
                 (allow-execute "Allow :execute tier tools (e.g. bash) in headless mode."
                                :flag t)
                 (output "Output format: plain (default) or json (JSON Lines to stdout). In json mode, logs are written to \"codabrus.log\" by default.")
                 (log-filename "A path to a file where to write logs. If not given, then they will be written to stdout.")
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
       (let* ((project-dir (if args
                             (pathname (first args))
                             (uiop:getcwd)))
              (session (make-session project-dir)))
         (handler-case
             (let* ((*model* (or model *model*))
                    (result (let ((completions::*tool-interceptor*
                                    (when json-p
                                      (lambda (fn-name call-args)
                                        (log:debug "Tool ~A is called" fn-name)
                                        (%emit-json-line
                                         `((:event . "tool-call")
                                           (:tool . ,fn-name)
                                           (:args . ,call-args)))
                                        (with-log-unhandled ()
                                          (let* ((fn-tool (gethash fn-name completions::*tools*))
                                                 (tool-result
                                                   (apply (slot-value fn-tool 'completions::fn)
                                                          (completions::map-args-to-parameters
                                                           fn-tool call-args))))
                                            (%emit-json-line
                                             `((:event . "tool-result")
                                               (:tool . ,fn-name)
                                               (:result . ,tool-result)))
                                            tool-result))))))
                              (run-session session prompt))))
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
               (uiop:quit 0))
           (headless-permission-denied (c)
             (format *error-output* "Permission denied: ~A~%" c)
             (uiop:quit 2))
           (error (e)
             (format *error-output* "Error: ~A~%" e)
             (when json-p
               (%emit-json-line `((:event . "finish")
                                  (:status . "error")
                                  (:message . ,(format nil "~A" e)))))
             (uiop:quit 1)))))
      (t
       ;; Server mode: start Slynk and MCP, then loop
       (40ants-slynk:start-slynk-if-needed)
       (when (uiop:getenv "MCP_PORT")
         (40ants-lisp-dev-mcp/core:start-server :port (parse-integer (uiop:getenv "MCP_PORT")))
         ;; (cl-mcp:start-http-server :port (1+ (parse-integer (uiop:getenv "MCP_PORT"))))
         )
       (loop do (sleep 10))))))
