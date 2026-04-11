(uiop:define-package #:codabrus/session
  (:use #:cl)
  (:import-from #:40ants-ai-agents/ai-agent
                #:ai-agent
                #:agent-completer)
  (:import-from #:completions
                #:prompt-token-count
                #:completion-token-count)
  (:import-from #:40ants-ai-agents/user-message
                #:user-message
                #:user-message-text)
  (:import-from #:40ants-ai-agents/ai-message
                #:ai-message
                #:ai-message-text)
  (:import-from #:40ants-ai-agents/state
                #:state
                #:state-messages)
  (:import-from #:40ants-ai-agents/generics
                #:add-message
                #:process)
  (:import-from #:codabrus/vars
                #:*project-dir*)
  (:import-from #:codabrus/tools/search
                #:search-file)
  (:import-from #:codabrus/tools/read-file
                #:read-file)
  (:import-from #:codabrus/tools/edit-file
                #:edit-file)
  (:import-from #:codabrus/tools/bash
                #:bash)
  (:export #:session
           #:session-project-dir
           #:session-state
           #:session-tokens-in
           #:session-tokens-out
           #:session-total-cost-usd
           #:make-session
           #:run-session))
(in-package #:codabrus/session)


(defparameter *system-prompt*
  "You are a code assistant.")

;; DeepSeek-V3 pricing (USD per million tokens); adjust for other models.
(defparameter *input-cost-per-million-tokens* 0.27d0)
(defparameter *output-cost-per-million-tokens* 1.10d0)

(defun compute-turn-cost (tokens-in tokens-out)
  (+ (* tokens-in  (/ *input-cost-per-million-tokens*  1000000.0d0))
     (* tokens-out (/ *output-cost-per-million-tokens* 1000000.0d0))))


(defclass session ()
  ((project-dir    :initarg :project-dir
                   :reader   session-project-dir)
   (state          :initarg  :state
                   :initform nil
                   :reader   session-state)
   (tokens-in      :initarg  :tokens-in
                   :initform 0
                   :reader   session-tokens-in)
   (tokens-out     :initarg  :tokens-out
                   :initform 0
                   :reader   session-tokens-out)
   (total-cost-usd :initarg  :total-cost-usd
                   :initform 0.0d0
                   :reader   session-total-cost-usd))
  (:documentation "Holds message history and project context for a multi-turn conversation.
Instances are immutable: run-session returns a new session with updated state rather than
modifying the existing one. This makes sessions safe to share across subagents and to
branch for parallel exploration."))


(defun make-session (project-dir &rest restargs &key state tokens-in tokens-out total-cost-usd)
  "Create a new session for PROJECT-DIR. STATE, TOKENS-IN, TOKENS-OUT, and TOTAL-COST-USD are optional."
  (declare (ignore state tokens-in tokens-out total-cost-usd))
  (apply #'make-instance 'session :project-dir project-dir restargs))


(defmethod describe-object ((session session) stream)
  (let ((messages (when (session-state session)
                    (state-messages (session-state session)))))
    (format stream "Session (project: ~A)~%" (session-project-dir session))
    (when messages
      (let ((user-msg (find-if (lambda (m) (typep m 'user-message)) messages))
            (ai-msg   (find-if (lambda (m) (typep m 'ai-message))   messages)))
        (when user-msg
          (format stream "~%User:~%~A~%" (user-message-text user-msg)))
        (when ai-msg
          (format stream "~%Assistant:~%~A~%" (ai-message-text ai-msg)))))))


(defun run-session (session message)
  "Add MESSAGE to SESSION, run the agent loop, and return the updated session."
  (let* ((*project-dir* (session-project-dir session))
         (current-state (session-state session))
         (new-state (if current-state
                        (add-message current-state (user-message message))
                        (state (list (user-message message)))))
         (agent (ai-agent *system-prompt*
                          :tools '(search-file read-file edit-file bash)))
         (final-state (process agent new-state))
         (completer    (agent-completer agent))
         (turn-in      (prompt-token-count completer))
         (turn-out     (completion-token-count completer))
         (turn-cost    (compute-turn-cost turn-in turn-out))
         (new-total-cost (+ (session-total-cost-usd session) turn-cost)))
    (log:info "[tokens: ~A in / ~A out | cost: $~,3F]" turn-in turn-out turn-cost)
    (make-session (session-project-dir session)
                  :state final-state
                  :tokens-in  (+ (session-tokens-in session)  turn-in)
                  :tokens-out (+ (session-tokens-out session) turn-out)
                  :total-cost-usd new-total-cost)))
