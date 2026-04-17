(uiop:define-package #:codabrus/repl
  (:use #:cl)
  (:import-from #:codabrus/session
                #:make-session
                #:run-session
                #:session-response
                #:session-id
                #:session-tokens-in
                #:session-tokens-out
                #:session-total-cost-usd
                #:session-state
                #:session-project-dir)
  (:import-from #:codabrus/vars
                #:*project-dir*
                #:*model*)
  (:import-from #:40ants-ai-agents/vars
                #:*api-key*)
  (:import-from #:40ants-ai-agents/llm-provider
                #:*max-turns*
                #:*max-cost-usd*
                #:prompt-token-count
                #:completion-token-count)
  (:import-from #:40ants-ai-agents/ai-agent
                #:agent-completer)
  (:import-from #:codabrus/secrets
                #:read-token)
  (:import-from #:40ants-ai-agents/state
                #:state-messages)
  (:import-from #:codabrus/message
                #:message
                #:message-role
                #:message-text)
  (:export #:setup
           #:chat
           #:chat*
           #:show
           #:cost
           #:history
           #:last-response
           #:*session*))
(in-package #:codabrus/repl)


(defvar *session* nil
  "Current REPL session. Bound by SETUP, updated by CHAT/CHAT*.")


(defun setup (&key (project-dir (uiop:getcwd))
                   (model "deepseek-chat")
                   api-key
                   max-turns
                   max-cost-usd)
  "Initialize API key, model, and session for REPL testing.
PROJECT-DIR — root directory the agent operates on (default: cwd).
MODEL       — model name (default: deepseek-chat).
API-KEY     — API key string; if nil, read from secrets.
MAX-TURNS   — abort after N round-trips (nil = unlimited).
MAX-COST    — abort if cost exceeds this USD amount (nil = unlimited)."
  (setf *api-key* (or api-key (read-token "deepseek")
                      (error "No API key. Pass :api-key or configure secrets.json")))
  (setf *model* model)
  (when max-turns
    (setf *max-turns* max-turns))
  (when max-cost-usd
    (setf *max-cost-usd* max-cost-usd))
  (setf *session* (make-session project-dir :model model))
  (format t "~&Ready. Model=~A Dir=~A Session=~A~%"
          model project-dir (session-id *session*))
  *session*)


(defun chat (message &key verbose)
  "Send MESSAGE to the current session, print the response, return the updated session.
Initializes with defaults if SETUP was not called."
  (unless *session*
    (setup))
  (let ((result (run-session *session* message
                             :tool-call-hook
                             (when verbose
                               (lambda (call-id fn-name raw-args)
                                 (declare (ignore call-id))
                                 (format t "~&  [CALL] ~A ~A~%" fn-name raw-args)))
                             :tool-result-hook
                             (when verbose
                               (lambda (call-id result)
                                 (declare (ignore call-id))
                                 (format t "~&  [RESULT] ~A~%"
                                         (let ((s (princ-to-string result)))
                                           (if (> (length s) 200)
                                               (concatenate 'string (subseq s 0 200) "...")
                                               s))))))))
    (setf *session* result)
    (let ((response (session-response result)))
      (when response
        (format t "~&~A~%" response))
      (cost))
    result))


(defun chat* (message)
  "Like CHAT but returns just the response text string."
  (session-response (chat message)))


(defun show ()
  "Print the full conversation history of the current session."
  (if (and *session* (session-state *session*))
      (dolist (msg (reverse (state-messages (session-state *session*))))
        (when (typep msg 'message)
          (format t "~&~A: ~A~%~%"
                  (message-role msg)
                  (or (message-text msg) "(no text)"))))
      (format t "~&No session. Call (setup) first.~%")))


(defun cost ()
  "Print token usage and cost for the current session."
  (if *session*
      (format t "~&[tokens: ~A in / ~A out | cost: $~,3F]~%"
              (session-tokens-in *session*)
              (session-tokens-out *session*)
              (session-total-cost-usd *session*))
      (format t "~&No session. Call (setup) first.~%")))


(defun history ()
  "Print the current session's conversation history."
  (show))


(defun last-response ()
  "Return the text of the last assistant response in the current session."
  (when *session*
    (session-response *session*)))
