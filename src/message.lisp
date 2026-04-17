(uiop:define-package #:codabrus/message
  (:use #:cl)
  (:import-from #:40ants-ai-agents/ai-agent
                #:to-api-messages
                #:make-response-message)
  (:import-from #:local-time
                #:now
                #:format-timestring)
  (:import-from #:serapeum
                #:dict)
  (:export #:message
           #:message-role
           #:message-parts
           #:message-created-at
           #:message-text
           #:text-part #:text-part-content
           #:tool-call-part #:tool-call-part-tool-name #:tool-call-part-call-id #:tool-call-part-raw-args
           #:tool-result-part #:tool-result-part-call-id #:tool-result-part-output
           #:step-end-part #:step-end-part-finish-reason #:step-end-part-tokens-in
           #:step-end-part-tokens-out #:step-end-part-cost-usd
           #:reasoning-part #:reasoning-part-content
           #:subtask-part #:subtask-part-agent-id #:subtask-part-task #:subtask-part-result
           #:compaction-part #:compaction-part-summary #:compaction-part-tokens-saved
           #:make-text-part
           #:make-tool-call-part
           #:make-tool-result-part
           #:make-step-end-part
           #:make-reasoning-part
           #:make-subtask-part
           #:make-compaction-part
           #:make-user-message
           #:make-assistant-message))
(in-package #:codabrus/message)


;;; Part classes

(defclass text-part ()
  ((content :initarg :content :type string :reader text-part-content)))

(defclass tool-call-part ()
  ((tool-name :initarg :tool-name :type string :reader tool-call-part-tool-name)
   (call-id :initarg :call-id :type string :reader tool-call-part-call-id)
   (raw-args :initarg :raw-args :type string :reader tool-call-part-raw-args)))

(defclass tool-result-part ()
  ((call-id :initarg :call-id :type string :reader tool-result-part-call-id)
   (output :initarg :output :type string :reader tool-result-part-output)))

(defclass step-end-part ()
  ((finish-reason :initarg :finish-reason :type keyword :reader step-end-part-finish-reason)
   (tokens-in :initarg :tokens-in :type integer :reader step-end-part-tokens-in)
   (tokens-out :initarg :tokens-out :type integer :reader step-end-part-tokens-out)
   (cost-usd :initarg :cost-usd :type float :reader step-end-part-cost-usd)))

(defclass reasoning-part ()
  ((content :initarg :content :type string :reader reasoning-part-content)))

(defclass subtask-part ()
  ((agent-id :initarg :agent-id :type string :reader subtask-part-agent-id)
   (task :initarg :task :type string :reader subtask-part-task)
   (result :initarg :result :type (or null string) :initform nil :reader subtask-part-result)))

(defclass compaction-part ()
  ((summary :initarg :summary :type string :reader compaction-part-summary)
   (tokens-saved :initarg :tokens-saved :type integer :reader compaction-part-tokens-saved)))


;;; Part constructors

(defun make-text-part (content)
  (make-instance 'text-part :content content))

(defun make-tool-call-part (tool-name call-id raw-args)
  (make-instance 'tool-call-part :tool-name tool-name :call-id call-id :raw-args raw-args))

(defun make-tool-result-part (call-id output)
  (make-instance 'tool-result-part :call-id call-id :output output))

(defun make-step-end-part (finish-reason tokens-in tokens-out cost-usd)
  (make-instance 'step-end-part
                 :finish-reason finish-reason
                 :tokens-in tokens-in
                 :tokens-out tokens-out
                 :cost-usd (coerce cost-usd 'float)))

(defun make-reasoning-part (content)
  (make-instance 'reasoning-part :content content))

(defun make-subtask-part (agent-id task &optional result)
  (make-instance 'subtask-part :agent-id agent-id :task task :result result))

(defun make-compaction-part (summary tokens-saved)
  (make-instance 'compaction-part :summary summary :tokens-saved tokens-saved))


;;; Timestamp helper

(defvar +iso-8601-format+
  '(:year "-" (:month 2) "-" (:day 2) "T" (:hour 2) ":" (:min 2) ":" (:sec 2)))

(defun %format-timestamp (timestamp)
  (format-timestring nil timestamp :format +iso-8601-format+))


;;; Message class

(defclass message (40ants-ai-agents/message:message)
  ((role :initarg :role
         :type (member :user :assistant :system)
         :reader message-role)
   (parts :initarg :parts
          :type list
          :reader message-parts)
   (created-at :initarg :created-at
               :type string
               :reader message-created-at)))


(defmethod print-object ((msg message) stream)
  (print-unreadable-object (msg stream :type t)
    (format stream "~A ~A part~:p"
            (message-role msg)
            (length (message-parts msg)))))


(defun make-user-message (text)
  (make-instance 'message
                 :role :user
                 :parts (list (make-text-part text))
                 :created-at (%format-timestamp (now))))

(defun make-assistant-message (parts)
  (make-instance 'message
                 :role :assistant
                 :parts parts
                 :created-at (%format-timestamp (now))))


(defun message-text (msg)
  "Extract the text from the first text-part in MSG, or NIL."
  (let ((tp (find-if (lambda (p) (typep p 'text-part)) (message-parts msg))))
    (when tp (text-part-content tp))))


;;; API format conversion

(defmethod to-api-messages ((msg message))
  (ecase (message-role msg)
    (:user
     (list (dict "role" "user"
                 "content" (or (message-text msg) ""))))
    (:system
     (list (dict "role" "system"
                 "content" (or (message-text msg) ""))))
    (:assistant
     (let ((tool-calls nil)
           (tool-results nil)
           (text-content nil))
       (dolist (part (message-parts msg))
         (typecase part
           (tool-call-part (push part tool-calls))
           (tool-result-part (push part tool-results))
           (text-part (setf text-content (text-part-content part)))
           (step-end-part nil)
           (reasoning-part nil)
           (subtask-part nil)
           (compaction-part nil)))
       (let ((entries nil))
         (when tool-calls
           (push (dict "role" "assistant"
                       "content" :null
                       "tool_calls" (coerce
                                     (loop for tc in (nreverse tool-calls)
                                           collect (dict "id" (tool-call-part-call-id tc)
                                                         "type" "function"
                                                         "function" (dict "name" (tool-call-part-tool-name tc)
                                                                          "arguments" (tool-call-part-raw-args tc))))
                                     'vector))
                 entries)
           (dolist (result (nreverse tool-results))
             (push (dict "role" "tool"
                         "tool_call_id" (tool-result-part-call-id result)
                         "content" (tool-result-part-output result))
                   entries)))
         (when text-content
           (push (dict "role" "assistant"
                       "content" text-content)
                 entries))
         (or (nreverse entries)
             (list (dict "role" "assistant"
                         "content" (or text-content "")))))))))


;;; make-response-message method

(defmethod make-response-message (response tool-events)
  (let ((parts nil))
    (dolist (event tool-events)
      (destructuring-bind (type call-id &rest data) event
        (ecase type
          (:tool-call
           (push (make-tool-call-part (first data) call-id (second data)) parts))
          (:tool-result
           (push (make-tool-result-part call-id (first data)) parts)))))
    (when (and response (not (string= response "")))
      (push (make-text-part response) parts))
    (make-assistant-message (nreverse parts))))
