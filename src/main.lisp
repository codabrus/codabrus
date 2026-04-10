(uiop:define-package #:codabrus/main
  (:use #:cl)
  (:import-from #:cl-mcp)
  (:import-from #:40ants-lisp-dev-mcp/core)
  (:import-from #:defmain
                #:defmain)
  (:import-from #:log)
  (:import-from #:40ants-slynk)
  (:import-from #:40ants-logging)
  (:export #:main))
(in-package #:codabrus/main)


(defmain (main) ()
  (let ((local-config-filename (probe-file ".local-config.lisp"))
        (current-dir (merge-pathnames (make-pathname :directory '(:relative)))))
    (cond
      (local-config-filename
       (log:info "Loading config from ~A"
                 local-config-filename)
       (load local-config-filename))
      (t
       (log:warn "There is no .local-config.lisp file. Current-directory is ~A"
                 current-dir))))

  (setf 40ants-ai-agents/vars:*api-key*
        (or (uiop:getenv "DEEPSEEK_API_TOKEN")
            (error "Set DEEPSEEK_API_TOKEN env var.")))

  (40ants-logging:setup-for-backend :level
                                    ;; Decided to log everything
                                    ;; until these log messages will hit the free limit of Yandex Cloud
                                    :debug)

  (40ants-slynk:start-slynk-if-needed)

  
  (when (uiop:getenv "MCP_PORT")
    (40ants-lisp-dev-mcp/core:start-server :port (parse-integer (uiop:getenv "MCP_PORT")))
    ;; (cl-mcp:start-http-server :port (1+ (parse-integer (uiop:getenv "MCP_PORT"))))
    )
  
  (loop do (sleep 10)))
