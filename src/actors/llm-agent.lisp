(uiop:define-package #:codabrus/actors/llm-agent
  (:use #:cl)
  (:import-from #:codabrus/actors/generic
                #:process-message
                #:make-clos-actor
                #:*message*)
  (:import-from #:codabrus/actors/callbacks
                #:call-callback
                #:callback-type)
  (:import-from #:codabrus/actors/tools/dispatcher
                #:make-tools-dispatcher)
  (:import-from #:codabrus/actors/tools/generic
                #:render-tool-result)
  (:import-from #:sento.stash
                #:stash
                #:unstash-all)
  (:import-from #:40ants-ai-agents/llm-provider
                #:get-single-completion)
  (:import-from #:40ants-ai-agents/utils
                #:json-parse)
  (:export #:make-llm-agent))
(in-package #:codabrus/actors/llm-agent)


(defclass llm-agent ()
  ((status :type (member :free :waiting-for-llm :waiting-for-tools)
           :initform :free
           :accessor llm-agent-status)
   (provider :initarg :provider
             :reader llm-agent-provider)
   (system-prompt :type string
                  :initarg :system-prompt
                  :initform ""
                  :reader llm-agent-system-prompt)
   (messages :type list
             :initform nil
             :accessor llm-agent-messages)
   (on-completion :type callback-type
                  :initform nil
                  :accessor llm-agent-on-completion)
   (dispatcher :initform nil
               :accessor llm-agent-dispatcher)
   (call-id-map :initform nil
                :accessor llm-agent-call-id-map)
   (tool-calls-data :type list
                    :initform nil
                    :accessor llm-agent-tool-calls-data)
   (interrupted :type boolean
                :initform nil
                :accessor llm-agent-interrupted)
   (tool-registry :type hash-table
                  :initarg :tool-registry
                  :reader llm-agent-tool-registry)))


(defmethod print-object ((obj llm-agent) stream)
  (print-unreadable-object (obj stream :type t)
    (format stream "~A" (llm-agent-status obj))))


(defun make-llm-agent (provider system-prompt tool-registry)
  (make-clos-actor 'llm-agent
                   :provider provider
                   :system-prompt system-prompt
                   :tool-registry tool-registry))


(defmethod process-message ((obj llm-agent) (message (eql :run)) &key messages on-completion)
  (cond
    ((not (eq (llm-agent-status obj) :free))
     (stash *message*)
     :stashed)
    (t
     (setf (llm-agent-messages obj) messages
           (llm-agent-on-completion obj) on-completion
           (llm-agent-interrupted obj) nil)
     (act:tell act:*self* :next-iteration))))


(defmethod process-message ((obj llm-agent) (message (eql :next-iteration)) &key)
  (setf (llm-agent-status obj) :waiting-for-llm)
  (let ((provider (llm-agent-provider obj))
        (api-messages (append (list (serapeum:dict "role" "system"
                                                   "content" (llm-agent-system-prompt obj)))
                              (llm-agent-messages obj)))
        (caller act:*self*))
    (tasks:with-context (act:*self*)
      (sento.tasks:task-async
       (lambda ()
         (handler-case
             (multiple-value-bind (type data updated-messages)
                 (get-single-completion provider api-messages)
               (act:ask caller
                        (list :on-llm-response
                              :type type
                              :data data
                              :messages updated-messages)))
           (error (e)
             (log:error "LLM call failed" e)
             (act:ask caller
                      (list :on-llm-response
                            :type :error
                            :data (princ-to-string e)
                            :messages nil)))))))))


(defmethod process-message ((obj llm-agent) (message (eql :on-llm-response))
                            &key type data messages)
  (when (llm-agent-interrupted obj)
    (%handle-interrupted obj)
    (return-from process-message))
  (ecase type
    (:text
     (%finish-with-text obj data messages))
    (:tool-calls
     (%dispatch-tool-calls obj data messages))
    (:error
     (let ((callback (llm-agent-on-completion obj)))
       (setf (llm-agent-status obj) :free
             (llm-agent-on-completion obj) nil)
       (when callback
         (call-callback callback :error :message data))
       (unstash-all)))))


(defun %finish-with-text (obj text messages)
  (let ((callback (llm-agent-on-completion obj)))
    (setf (llm-agent-status obj) :free
          (llm-agent-on-completion obj) nil)
    (when callback
      (call-callback callback :completed :text text :messages messages))
    (unstash-all)))


(defun %dispatch-tool-calls (obj tool-calls messages)
  (let ((tool-specs nil)
        (call-id-map (make-hash-table :test 'eq))
        (registry (llm-agent-tool-registry obj)))
    (loop for tc in tool-calls
          for call-id = (gethash "id" tc)
          for func = (gethash "function" tc)
          for fn-name = (gethash "name" func)
          for raw-args = (gethash "arguments" func)
          for args = (json-parse raw-args)
          for factory = (gethash (string-downcase fn-name) registry)
          do (let* ((spec (funcall factory args))
                    (actor (apply (first spec) (rest spec))))
               (setf (gethash actor call-id-map)
                     (cons call-id fn-name))
               (push spec tool-specs)))
    (setf (llm-agent-messages obj) messages
          (llm-agent-call-id-map obj) call-id-map
          (llm-agent-tool-calls-data obj) tool-calls
          (llm-agent-status obj) :waiting-for-tools)
    (let ((dispatcher (make-tools-dispatcher)))
      (setf (llm-agent-dispatcher obj) dispatcher)
      (act:ask dispatcher
               (list :run
                     :tool-specs tool-specs
                     :on-completion act:*self*)))))


(defmethod process-message ((obj llm-agent) (message (eql :completed))
                            &key actor tools)
  (declare (ignore actor))
  (when (llm-agent-interrupted obj)
    (%handle-interrupted obj)
    (return-from process-message))
  (let ((call-id-map (llm-agent-call-id-map obj))
        (tool-answers nil))
    (loop for tool-actor in tools
          for (call-id . tool-name) = (gethash tool-actor call-id-map)
          for result = (render-tool-result (act:ask-s tool-actor :get-state))
          do (push (serapeum:dict "role" "tool"
                                  "tool_call_id" call-id
                                  "content" result)
                   tool-answers))
    (let ((assistant-msg (serapeum:dict "role" "assistant"
                                        "content" :null
                                        "tool_calls" (coerce (llm-agent-tool-calls-data obj) 'vector))))
      (setf (llm-agent-messages obj)
            (append (llm-agent-messages obj)
                    (list assistant-msg)
                    (nreverse tool-answers))
            (llm-agent-call-id-map obj) nil
            (llm-agent-tool-calls-data obj) nil
            (llm-agent-dispatcher obj) nil)
      (act:tell act:*self* :next-iteration))))


(defmethod process-message ((obj llm-agent) (message (eql :interrupted))
                            &key actor)
  (declare (ignore actor))
  (%handle-interrupted obj))


(defmethod process-message ((obj llm-agent) (message (eql :interrupt)) &key)
  (setf (llm-agent-interrupted obj) t)
  (case (llm-agent-status obj)
    (:waiting-for-tools
     (when (llm-agent-dispatcher obj)
       (act:ask (llm-agent-dispatcher obj) (list :interrupt))))
    (:free
     (let ((callback (llm-agent-on-completion obj)))
       (setf (llm-agent-status obj) :free
             (llm-agent-on-completion obj) nil
             (llm-agent-interrupted obj) nil)
       (when callback
         (call-callback callback :interrupted :actor act:*self*))))))


(defun %handle-interrupted (obj)
  (let ((callback (llm-agent-on-completion obj)))
    (setf (llm-agent-status obj) :free
          (llm-agent-on-completion obj) nil
          (llm-agent-messages obj) nil
          (llm-agent-call-id-map obj) nil
          (llm-agent-tool-calls-data obj) nil
          (llm-agent-dispatcher obj) nil
          (llm-agent-interrupted obj) nil)
    (when callback
      (call-callback callback :interrupted :actor act:*self*))
    (unstash-all)))
