(uiop:define-package #:codabrus/actors/tools/dispatcher
  (:use #:cl)
  (:import-from #:codabrus/actors/generic
                #:process-message
                #:make-clos-actor)
  (:import-from #:codabrus/actors/callbacks
                #:call-callback
                #:callback-type)
  (:export #:make-tools-dispatcher))
(in-package #:codabrus/actors/tools/dispatcher)


(defclass tools-dispatcher ()
  ((tool-specs :type list
               :initarg :tool-specs
               :reader tools-dispatcher-tool-specs)
   (pending :type list
            :initform nil
            :accessor tools-dispatcher-pending)
   (completed :type list
              :initform nil
              :accessor tools-dispatcher-completed)
   (on-completion :type callback-type
                  :initform nil
                  :accessor tools-dispatcher-on-completion)))


(defmethod print-object ((obj tools-dispatcher) stream)
  (print-unreadable-object (obj stream :type t)
    (let ((total (+ (length (tools-dispatcher-pending obj))
                    (length (tools-dispatcher-completed obj)))))
      (format stream "~D/~D tools completed"
              (length (tools-dispatcher-completed obj))
              total))))


(defun make-tools-dispatcher (tool-specs)
  (make-clos-actor 'tools-dispatcher
                   :tool-specs tool-specs))


(defmethod process-message ((obj tools-dispatcher) (message (eql :run)) &key on-completion)
  (when on-completion
    (setf (tools-dispatcher-on-completion obj) on-completion))
  (loop for spec in (tools-dispatcher-tool-specs obj)
        for constructor = (first spec)
        for args = (rest spec)
        for actor = (apply constructor args)
        do (push actor (tools-dispatcher-pending obj))
           (act:ask actor (list :run :on-completion act:*self*)))
  (when (null (tools-dispatcher-tool-specs obj))
    (log:info "No tools to dispatch")))


(defmethod process-message ((obj tools-dispatcher) (message (eql :completed)) &key actor)
  (setf (tools-dispatcher-pending obj)
        (remove actor (tools-dispatcher-pending obj)))
  (push actor (tools-dispatcher-completed obj))
  (when (null (tools-dispatcher-pending obj))
    (log:info "All tools completed"
              (length (tools-dispatcher-completed obj)))
    (when (tools-dispatcher-on-completion obj)
      (call-callback (tools-dispatcher-on-completion obj)
                     :completed
                     :actor act:*self*
                     :tools (tools-dispatcher-completed obj)))))
