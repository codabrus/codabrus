(uiop:define-package #:codabrus/actors/tools/dispatcher
  (:use #:cl)
  (:import-from #:codabrus/actors/generic
                #:process-message
                #:make-clos-actor
                #:*message*)
  (:import-from #:codabrus/actors/callbacks
                #:call-callback
                #:callback-type)
  (:import-from #:sento.stash
                #:stash
                #:unstash-all)
  (:export #:make-tools-dispatcher))
(in-package #:codabrus/actors/tools/dispatcher)


(defclass tools-dispatcher ()
  ((status :type (member :free :busy)
           :initform :free
           :accessor tools-dispatcher-status)
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
      (format stream "~A ~D/~D tools completed"
              (tools-dispatcher-status obj)
              (length (tools-dispatcher-completed obj))
              total))))


(defun make-tools-dispatcher ()
  (make-clos-actor 'tools-dispatcher))


(defmethod process-message ((obj tools-dispatcher) (message (eql :run)) &key tool-specs on-completion)
  (cond
    ((eq (tools-dispatcher-status obj) :busy)
     (stash *message*)
     :stashed)
    (t
     (setf (tools-dispatcher-status obj) :busy
           (tools-dispatcher-pending obj) nil
           (tools-dispatcher-completed obj) nil
           (tools-dispatcher-on-completion obj) on-completion)
     (loop for spec in tool-specs
           for constructor = (first spec)
           for args = (rest spec)
           for actor = (apply constructor args)
           do (push actor (tools-dispatcher-pending obj))
              (act:ask actor (list :run :on-completion act:*self*)))
     (when (null tool-specs)
       (log:info "No tools to dispatch")
       (%finish-round obj))
     (values))))


(defmethod process-message ((obj tools-dispatcher) (message (eql :completed)) &key actor)
  (setf (tools-dispatcher-pending obj)
        (remove actor (tools-dispatcher-pending obj)))
  (push actor (tools-dispatcher-completed obj))
  (when (null (tools-dispatcher-pending obj))
    (%finish-round obj)))


(defun %finish-round (obj)
  (log:info "All tools completed"
            (length (tools-dispatcher-completed obj)))
  (when (tools-dispatcher-on-completion obj)
    (call-callback (tools-dispatcher-on-completion obj)
                   :completed
                   :actor act:*self*
                   :tools (tools-dispatcher-completed obj)))
  (setf (tools-dispatcher-status obj) :free)
  (unstash-all))


(defmethod process-message ((obj tools-dispatcher) (message (eql :interrupt)) &key)
  (when (eq (tools-dispatcher-status obj) :busy)
    (loop for tool-actor in (tools-dispatcher-pending obj)
          do (act:ask tool-actor (list :interrupt)))
    (let ((callback (tools-dispatcher-on-completion obj)))
      (setf (tools-dispatcher-status obj) :free
            (tools-dispatcher-pending obj) nil
            (tools-dispatcher-completed obj) nil
            (tools-dispatcher-on-completion obj) nil)
      (when callback
        (call-callback callback :interrupted :actor act:*self*))
      (unstash-all))))


(defmethod process-message ((obj tools-dispatcher) (message (eql :interrupted)) &key actor)
  (declare (ignore actor)))
