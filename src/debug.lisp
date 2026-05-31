(uiop:define-package #:codabrus/debug
  (:use #:cl)
  (:import-from #:bordeaux-threads-2
                #:thread-alive-p)
  (:import-from #:sento.actor-cell)
  (:import-from #:sento.messageb)
  (:import-from #:sento.actor-system)
  (:import-from #:sento.actor-context)
  (:import-from #:codabrus/frontend/diagram/session
                #:*current-session-actor*)
  (:export
    #:actors-info
    #:get-dispatch-thread))
(in-package #:codabrus/debug)


(defun ensure-system (system-or-actor)
  (typecase system-or-actor
    (sento.actor-system:actor-system system-or-actor)
    (t
       (sento.actor-context:system system-or-actor))))


(defun actors-info (system-or-actor &key (verbose nil))
  (let* ((system (ensure-system system-or-actor))
         (actors (append (sento.actor-system::%all-actors system :user)
                         (sento.actor-system::%all-actors system :internal))))
    (loop for actor in (sort
                        ;; Sort is destructive, so we have to copy actors list here
                        (copy-list actors)
                        #'string<
                        :key #'sento.actor-cell:name)
          for msgbox = (sento.actor-cell:msgbox actor)
          for pinned = (typep msgbox 'sento.messageb:message-box/bt)
          for thread = (when pinned
                         (slot-value msgbox 'sento.messageb::queue-thread))
          for queue = (slot-value msgbox
                                  'sento.messageb::queue)
          do (if thread
               (format t "~A: ~A (~A) ~@[msgbox-name=~A~]~%"
                       (sento.actor-cell:name actor)
                       (sento.queue:queued-count queue)
                       (if (thread-alive-p thread)
                         "thread alive"
                         "thread died")
                       (when verbose
                         (sento.messageb::name msgbox)))
               (format t "~A: ~A~%"
                       (sento.actor-cell:name actor)
                       (sento.queue:queued-count queue))))))


;; Имена у диспатч акторов такие: dispatch(SHARED)-worker-1, dispatch(SHARED)-worker-2, dispatch(SHARED)-worker-3, ...

(defun get-dispatch-thread (thread-num)
  (let* ((system (ensure-system *current-session-actor*))
         (name (format nil "dispatch(SHARED)-worker-~A" thread-num))
         (actors (sento.actor-system::%all-actors system :internal)))
    (let ((actor (find name actors :key #'sento.actor-cell:name :test #'string=)))
      (when actor
        (let ((msgbox (sento.actor-cell:msgbox actor)))
          (when (typep msgbox 'sento.messageb:message-box/bt)
            (values (slot-value msgbox 'sento.messageb::queue-thread)
                    actor)))))))
