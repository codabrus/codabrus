(uiop:define-package #:codabrus/actors/actor-system
  (:use #:cl)
  (:import-from #:sento.actor-system
                #:make-actor-system)
  (:import-from #:sento.actor-context
                #:shutdown)
  (:import-from #:codabrus/actors/vars
                #:*actor-system*)
  (:export #:start-actor-system
           #:stop-actor-system
           #:ensure-actor-system))
(in-package #:codabrus/actors/actor-system)


(defun start-actor-system (&optional config)
  "Create and store a new Sento actor-system in *ACTOR-SYSTEM*.
CONFIG is an optional plist passed to MAKE-ACTOR-SYSTEM.
Signals an error if an actor-system is already running."
  (when *actor-system*
    (error "Actor system is already running. Call STOP-ACTOR-SYSTEM first."))
  (setf *actor-system*
        (if config
            (make-actor-system config)
            (make-actor-system)))
  (log:info "Actor system started")
  *actor-system*)


(defun stop-actor-system ()
  "Shut down the global actor-system and set *ACTOR-SYSTEM* to NIL."
  (when *actor-system*
    (log:info "Actor system shutting down")
    (shutdown *actor-system*)
    (setf *actor-system* nil)))


(defun ensure-actor-system (&optional config)
  "Return *ACTOR-SYSTEM*, starting it first if necessary."
  (or *actor-system*
      (start-actor-system config)))
