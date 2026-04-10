(uiop:define-package #:codabrus/session
  (:use #:cl)
  (:import-from #:40ants-ai-agents/ai-agent
                #:ai-agent)
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
           #:make-session
           #:run-session))
(in-package #:codabrus/session)


(defparameter *system-prompt*
  "You are a code assistant.")


(defclass session ()
  ((project-dir :initarg :project-dir
                :reader   session-project-dir)
   (state       :initarg  :state
                :initform nil
                :reader   session-state))
  (:documentation "Holds message history and project context for a multi-turn conversation.
Instances are immutable: run-session returns a new session with updated state rather than
modifying the existing one. This makes sessions safe to share across subagents and to
branch for parallel exploration."))


(defun make-session (project-dir &rest restargs &key state)
  "Create a new session for PROJECT-DIR. STATE is optional (defaults to nil)."
  (declare (ignore state))
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
         (final-state (process agent new-state)))
    (make-session (session-project-dir session) :state final-state)))
