(uiop:define-package #:codabrus/frontend/diagram/session
  (:use #:cl)
  (:import-from #:serapeum
                #:dict)
  (:import-from #:bordeaux-threads-2
                #:make-lock
                #:with-lock-held)
  (:import-from #:codabrus/actors/actor-system
                #:ensure-actor-system)
  (:import-from #:codabrus/actors/llm-agent
                #:llm-agent-messages
                #:llm-agent-status
                #:make-llm-agent)
  (:import-from #:codabrus/actors/vars
                #:*actor-system*)
  (:export #:*current-session-actor*
           #:send-user-message
           #:agent-free-p
           #:get-session-messages
           #:reset-session
           #:get-stream-chunks
           #:clear-stream-buffer
           #:agent-status))
(in-package #:codabrus/frontend/diagram/session)


(defvar *current-session-actor* nil)

(defvar *stream-buffer* "")
(defvar *stream-lock* (bt2:make-lock :name "stream-buffer"))


(defun streaming-callback (chunk)
  (with-lock-held (*stream-lock*)
    (setf *stream-buffer* (concatenate 'string *stream-buffer* chunk))))


(defun get-stream-chunks ()
  (with-lock-held (*stream-lock*)
    (prog1 *stream-buffer*
      (setf *stream-buffer* ""))))


(defun clear-stream-buffer ()
  (with-lock-held (*stream-lock*)
    (setf *stream-buffer* "")))


(defun agent-status ()
  (if *current-session-actor*
      (let ((state (slot-value *current-session-actor* 'sento.actor-cell:state)))
        (llm-agent-status state))
      :free))


(defun make-tool-registry ()
  (let ((registry (make-hash-table :test 'equal)))
    (setf (gethash "bash" registry)
          (lambda (args)
            (list 'codabrus/actors/tools/bash:make-bash
                  (gethash "command" args))))
    registry))


(defun get-api-key ()
  (or (uiop:getenv "DEEPSEEK_API_TOKEN")
      (error "Set DEEPSEEK_API_TOKEN env var")))


(defun make-provider ()
  (make-instance '40ants-ai-agents/llm-provider/openai:openai-provider
                 :endpoint "https://api.deepseek.com/chat/completions"
                 :api-key (get-api-key)
                 :model "deepseek-chat"
                 :tools '(codabrus/tools/bash:bash)))


(defun start-agent (user-message)
  (ensure-actor-system)
  (clear-stream-buffer)
  (let* ((provider (make-provider))
         (registry (make-tool-registry))
         (prompt "You are a helpful assistant with access to a bash tool. Use it when needed.")
         (agent (make-llm-agent provider prompt registry
                                :streaming-callback #'streaming-callback)))
    (setf *current-session-actor* agent)
    (act:ask agent
             (list :run
                   :messages (list (dict "role" "user"
                                        "content" user-message))
                   :on-completion nil))
    agent))


(defun get-session-messages ()
  (when *current-session-actor*
    (let ((state (slot-value *current-session-actor* 'sento.actor-cell:state)))
      (llm-agent-messages state))))


(defun agent-free-p ()
  (when *current-session-actor*
    (let ((state (slot-value *current-session-actor* 'sento.actor-cell:state)))
      (eq (llm-agent-status state) :free))))


(defun send-user-message (text)
  (cond
    ((null *current-session-actor*)
     (start-agent text))
    ((agent-free-p)
     (clear-stream-buffer)
     (let* ((state (slot-value *current-session-actor* 'sento.actor-cell:state))
            (messages (llm-agent-messages state)))
       (setf (llm-agent-messages state)
             (append messages (list (dict "role" "user"
                                         "content" text))))
       (act:ask *current-session-actor*
                (list :run
                      :messages (llm-agent-messages state)
                      :on-completion nil))
       *current-session-actor*))
    (t
     (log:warn "Agent is busy, ignoring message")
     nil)))


(defun reset-session ()
  (when *current-session-actor*
    (act:ask *current-session-actor* (list :interrupt)))
  (setf *current-session-actor* nil)
  (clear-stream-buffer))
