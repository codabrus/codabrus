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
                #:get-session-messages
                #:get-stream-chunks
                #:agent-status)
  (:import-from #:codabrus/frontend/diagram/builder
                #:build-diagram-data
                #:diagram-to-json)
  (:export #:diagram-sse-route
           #:stream-sse-route))
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


(defclass stream-sse-route (route)
  ())


(defun sse-encode-data (text)
  (with-output-to-string (s)
    (loop for ch across text
          do (case ch
               (#\Newline (write-string "\\n" s))
               (#\\ (write-string "\\\\" s))
               (t (write-char ch s))))))


(defun sse-write-event (output-stream event data)
  (format output-stream "event: ~A~%data: ~A~%~%" event data)
  (finish-output output-stream))


(defun stream-events-stream (env output-stream)
  (declare (ignore env))
  (log:info "SSE client connected to stream-events")
  (sse-write-event output-stream "stream-clear" "")
  (let ((prev-status :free)
        (done-sent nil))
    (loop
      (let ((chunks (get-stream-chunks)))
        (when (plusp (length chunks))
          (sse-write-event output-stream "stream-chunk" (sse-encode-data chunks))
          (setf done-sent nil)))
      (let ((status (agent-status)))
        (when (and (eq prev-status :free)
                   (not (eq status :free)))
          (sse-write-event output-stream "stream-clear" ""))
        (when (and (eq status :free) (not done-sent) (not (eq prev-status :free)))
          (sse-write-event output-stream "stream-done" "")
          (setf done-sent t))
        (setf prev-status status))
      (sleep 0.1))))


(defmethod serve ((route stream-sse-route) env)
  (funcall (serve-sse 'stream-events-stream) env))
