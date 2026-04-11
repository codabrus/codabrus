(uiop:define-package #:codabrus/main
  (:use #:cl)
  (:import-from #:cl-mcp)
  (:import-from #:40ants-lisp-dev-mcp/core)
  (:import-from #:defmain
                #:defmain)
  (:import-from #:log)
  (:import-from #:40ants-slynk)
  (:import-from #:40ants-logging)
  (:import-from #:codabrus/session
                #:make-session
                #:run-session
                #:session-response)
  (:import-from #:codabrus/secrets
                #:read-token)
  (:import-from #:codabrus/vars
                #:*model*)
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


(defmain (main) ((prompt "Run a single task and exit."
                          :short "p")
                 (model "Override the default model for this run."
                        :short "m")
                 &rest args)
  "Codabrus — hackable AI code assistant."

  (40ants-logging:setup-for-backend :level :debug)
  (%setup-common)

  (cond
    (prompt
     ;; CLI mode: run one task and exit
     (let* ((project-dir (if args
                             (pathname (first args))
                             (uiop:getcwd)))
            (session (make-session project-dir)))
       (let ((*model* (or model *model*)))
         (let ((result (run-session session prompt)))
           (let ((response (session-response result)))
             (when response
               (format t "~A~%" response)))
           (uiop:quit 0)))))
    (t
     ;; Server mode: start Slynk and MCP, then loop
     (40ants-slynk:start-slynk-if-needed)
     (when (uiop:getenv "MCP_PORT")
       (40ants-lisp-dev-mcp/core:start-server :port (parse-integer (uiop:getenv "MCP_PORT")))
       ;; (cl-mcp:start-http-server :port (1+ (parse-integer (uiop:getenv "MCP_PORT"))))
       )
     (loop do (sleep 10)))))
