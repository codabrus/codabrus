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
  (:export #:diagram-sse-route))
(in-package #:codabrus/frontend/routes)


(defclass diagram-sse-route (route)
  ())


(defun diagram-events-stream (env output-stream)
  (declare (ignore env))
  (log:info "SSE client connected to diagram-events")
  (loop with counter = 2
        with last-id = "n2"
        for new-id = (format nil "n~A" (incf counter))
        for x = (+ 80 (random 400))
        for y = (+ 80 (random 300))
        do (sleep 5)
           (let ((payload (format nil "{\"id\":\"~A\",\"x\":~D,\"y\":~D,\"width\":100,\"height\":40,\"label\":\"Block ~A\",\"source\":\"~A\"}"
                                  new-id x y counter last-id)))
             (format output-stream "event: add-node~%data: ~A~%~%" payload)
             (finish-output output-stream)
             (log:info "Sent SSE add-node event: ~A" new-id))
           (setf last-id new-id)))


(defmethod serve ((route diagram-sse-route) env)
  (funcall (serve-sse 'diagram-events-stream) env))
