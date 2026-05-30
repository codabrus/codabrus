(uiop:define-package #:codabrus/frontend/routes
  (:use #:cl)
  (:import-from #:40ants-routes/route
                #:route)
  (:shadowing-import-from #:40ants-routes/defroutes
                          #:get)
  (:import-from #:reblocks/routes
                #:serve)
  (:import-from #:clack-sse
                #:serve-sse)
  (:import-from #:log)
  (:import-from #:codabrus/frontend/diagram/session
                #:*current-session-actor*
                #:get-session-messages)
  (:import-from #:codabrus/frontend/diagram/builder
                #:build-diagram-data
                #:diagram-to-json)
  (:export #:diagram-sse-route))
(in-package #:codabrus/frontend/routes)


(defclass diagram-sse-route (route)
  ())


(defun diagram-events-stream (env output-stream)
  (declare (ignore env))
  (log:info "SSE client connected to diagram-events")
  (let ((last-msg-count -1))
    (loop
      (let* ((messages (get-session-messages))
             (msg-count (length messages)))
        (when (/= msg-count last-msg-count)
          (let* ((data (build-diagram-data messages))
                 (json (diagram-to-json data)))
            (format output-stream "event: init-diagram~%data: ~A~%~%" json)
            (finish-output output-stream)
            (log:info "Sent SSE init-diagram event with ~A messages" msg-count))
          (setf last-msg-count msg-count)))
      (sleep 1))))


(defmethod serve ((route diagram-sse-route) env)
  (funcall (serve-sse 'diagram-events-stream) env))
