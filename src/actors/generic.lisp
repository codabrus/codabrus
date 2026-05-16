(uiop:define-package #:codabrus/actors/generic
  (:use #:cl)
  (:import-from #:codabrus/actors/vars
                #:*actor-system*)
  (:import-from #:codabrus/actors/actor
                #:stashing-actor)
  (:export #:process-message
           #:make-clos-actor
           #:*message*))
(in-package #:codabrus/actors/generic)


(defvar *message* nil
  "The raw message plist as received by the actor's receive function.
Bound dynamically so that process-message handlers can access it for stashing.")


(defgeneric process-message (obj name &key &allow-other-keys)
  (:documentation "Define a method for this generic function to make object of some type handle a message with NAME argument given as a keyword."))


(defmethod process-message ((obj t) (method (eql :get-state)) &key)
  "Just returning the current object because it is a current actor state."
  obj)


(defun make-clos-actor (class &rest initargs &key name &allow-other-keys)
  (let ((other-args (alexandria:remove-from-plist initargs :name)))
    (ac:actor-of *actor-system*
                 :name name
                 :type 'stashing-actor
                 :receive (lambda (message)
                            (let ((*message* message))
                              (let ((result (apply #'process-message
                                                   act:*state*
                                                   (uiop:ensure-list message))))
                                (if (eq result :stashed)
                                    (cons :no-reply act:*state*)
                                    result))))
                 :state (apply #'make-instance
                               class
                               other-args))))
