(uiop:define-package #:codabrus/session
  (:use #:cl)
  (:import-from #:40ants-ai-agents/ai-agent
                 #:ai-agent
                 #:agent-completer
                 #:make-response-message)
  (:import-from #:40ants-ai-agents/llm-provider
                 #:prompt-token-count
                 #:completion-token-count
                 #:call-tool
                 #:json-encode)
  (:import-from #:event-emitter)
  (:import-from #:40ants-ai-agents/state
                 #:state
                 #:state-messages)
  (:import-from #:40ants-ai-agents/generics
                 #:add-message
                 #:process)
  (:import-from #:codabrus/vars
                 #:*project-dir*
                 #:*model*)
  (:import-from #:codabrus/tools/search
                 #:search-file)
  (:import-from #:codabrus/tools/read-file
                 #:read-file)
  (:import-from #:codabrus/tools/edit-file
                 #:edit-file)
  (:import-from #:codabrus/tools/bash
                 #:bash)
  (:import-from #:codabrus/message
                 #:message
                 #:message-role
                 #:message-parts
                 #:message-text
                 #:message-created-at
                 #:make-user-message
                 #:make-step-end-part)
  (:import-from #:uuid
                 #:make-v4-uuid)
  (:import-from #:alexandria
                 #:remove-from-plist)
  (:import-from #:local-time
                 #:now
                 #:format-timestring)
  (:export #:session
           #:session-id
           #:session-project-dir
           #:session-model
           #:session-state
           #:session-tokens-in
           #:session-tokens-out
           #:session-total-cost-usd
           #:session-created-at
           #:session-updated-at
           #:session-response
           #:make-session
           #:run-session
           #:touch-session
           #:compute-turn-cost
           #:with-provider-tool-hooks))
(in-package #:codabrus/session)


(defparameter *system-prompt*
  "You are a code assistant.")

(defparameter *input-cost-per-million-tokens* 0.27d0)
(defparameter *output-cost-per-million-tokens* 1.10d0)

(defun compute-turn-cost (tokens-in tokens-out)
  (+ (* tokens-in  (/ *input-cost-per-million-tokens*  1000000.0d0))
     (* tokens-out (/ *output-cost-per-million-tokens* 1000000.0d0))))


(defclass session ()
  ((id             :initarg :id
                   :reader   session-id)
   (project-dir    :initarg :project-dir
                   :reader   session-project-dir)
   (model          :initarg  :model
                   :initform "deepseek-chat"
                   :reader   session-model)
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
                   :reader   session-total-cost-usd)
   (created-at     :initarg  :created-at
                   :reader   session-created-at)
   (updated-at     :initarg  :updated-at
                   :reader   session-updated-at))
  (:documentation "Holds message history and project context for a multi-turn conversation.
Instances are immutable: run-session returns a new session with updated state rather than
modifying the existing one. This makes sessions safe to share across subagents and to
branch for parallel exploration."))


(defvar +iso-8601-format+
  '(:year "-" (:month 2) "-" (:day 2) "T" (:hour 2) ":" (:min 2) ":" (:sec 2)))

(defun %format-timestamp (timestamp)
  (format-timestring nil timestamp :format +iso-8601-format+))

(defun make-session (project-dir &rest restargs
                     &key id model state tokens-in tokens-out total-cost-usd
                       created-at updated-at)
  "Create a new session for PROJECT-DIR."
  (declare (ignore model state tokens-in tokens-out total-cost-usd))
  (let ((uuid (or id (format nil "~A" (make-v4-uuid))))
        (ts (or created-at (%format-timestamp (now)))))
    (apply #'make-instance 'session
           :project-dir project-dir
           :id uuid
           :created-at ts
           :updated-at (or updated-at ts)
           (alexandria:remove-from-plist restargs
                                         :id :created-at :updated-at))))


(defmethod describe-object ((session session) stream)
  (format stream "Session ~A (project: ~A)~%" (session-id session) (session-project-dir session))
  (let ((messages (when (session-state session)
                    (state-messages (session-state session)))))
    (when messages
      (loop for msg in messages
            when (typep msg 'message)
              do (format stream "~%~A:~%~A~%"
                         (message-role msg)
                         (or (message-text msg) "(no text)"))))))


(defun touch-session (session)
  "Return a copy of SESSION with updated-at set to now."
  (make-session (session-project-dir session)
                :id (session-id session)
                :model (session-model session)
                :state (session-state session)
                :tokens-in (session-tokens-in session)
                :tokens-out (session-tokens-out session)
                :total-cost-usd (session-total-cost-usd session)
                :created-at (session-created-at session)
                :updated-at (%format-timestamp (now))))


(defmacro with-provider-tool-hooks ((provider on-call on-result) &body body)
  "Set up :tool-call and :tool-result event listeners on PROVIDER for the duration of BODY."
  (let ((p (gensym "PROVIDER"))
        (call-handler (gensym "CALL-HANDLER"))
        (result-handler (gensym "RESULT-HANDLER")))
    `(let* ((,p ,provider)
            (,call-handler ,on-call)
            (,result-handler ,on-result))
       (event-emitter:on :tool-call ,p ,call-handler)
       (event-emitter:on :tool-result ,p ,result-handler)
       (unwind-protect
            (progn ,@body)
         (event-emitter:remove-listener ,p :tool-call ,call-handler)
         (event-emitter:remove-listener ,p :tool-result ,result-handler)))))


(defun run-session (session message &key tool-call-hook tool-result-hook)
  "Add MESSAGE to SESSION, run the agent loop, and return the updated session.
Tool events are always captured into part-based message history. Optional
TOOL-CALL-HOOK and TOOL-RESULT-HOOK are called for display/logging purposes."
  (let* ((*project-dir* (session-project-dir session))
         (current-state (session-state session))
         (new-state (if current-state
                        (add-message current-state (make-user-message message))
                        (state (list (make-user-message message)))))
         (effective-model (session-model session))
         (agent (ai-agent *system-prompt*
                          :tools '(search-file read-file edit-file bash)
                          :model effective-model))
         (completer (agent-completer agent))
         (collected-events '())
         (internal-call-hook
           (lambda (call-id fn-name args)
             (push (list :tool-call call-id fn-name (json-encode args))
                   collected-events)
             (when tool-call-hook
               (funcall tool-call-hook call-id fn-name args))))
         (internal-result-hook
           (lambda (call-id result)
             (push (list :tool-result call-id result)
                   collected-events)
             (when tool-result-hook
               (funcall tool-result-hook call-id result))))
         (final-state
           (with-provider-tool-hooks (completer internal-call-hook internal-result-hook)
             (process agent new-state)))
         (turn-in      (prompt-token-count completer))
         (turn-out     (completion-token-count completer))
         (turn-cost    (compute-turn-cost turn-in turn-out))
         (new-total-cost (+ (session-total-cost-usd session) turn-cost)))
    (log:debug "[tokens: ~A in / ~A out | cost: $~,3F]" turn-in turn-out turn-cost)
    (let* ((msgs (state-messages final-state))
           (assistant-msg (first msgs))
           (rebuilt-msg
             (if collected-events
                 (make-response-message (message-text assistant-msg)
                                        (nreverse collected-events))
                 assistant-msg))
           (enriched-msg (make-instance 'message
                                        :role :assistant
                                        :parts (append (message-parts rebuilt-msg)
                                                       (list (make-step-end-part
                                                              :stop turn-in turn-out turn-cost)))
                                        :created-at (message-created-at rebuilt-msg)))
           (enriched-state (state (cons enriched-msg (rest msgs)))))
      (make-session (session-project-dir session)
                    :id (session-id session)
                    :model effective-model
                    :state enriched-state
                    :tokens-in  (+ (session-tokens-in session)  turn-in)
                    :tokens-out (+ (session-tokens-out session) turn-out)
                    :total-cost-usd new-total-cost
                    :created-at (session-created-at session)
                    :updated-at (%format-timestamp (now))))))


(defun session-response (session)
  "Return the text of the last AI message in SESSION, or NIL."
  (when (session-state session)
    (let ((msgs (state-messages (session-state session))))
      (let ((assistant-msg (find-if (lambda (m)
                                      (and (typep m 'message)
                                           (eq (message-role m) :assistant)))
                                    msgs)))
        (when assistant-msg
          (message-text assistant-msg))))))
