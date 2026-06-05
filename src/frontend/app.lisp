(uiop:define-package #:codabrus/frontend/app
  (:use #:cl)
  (:import-from #:reblocks/app
                #:defapp)
  (:import-from #:reblocks/routes
                #:page)
  (:import-from #:reblocks/widgets/funcall-widget
                #:make-funcall-widget)
  (:import-from #:reblocks/html
                #:with-html)
  (:import-from #:reblocks/widget
                #:render)
  (:shadowing-import-from #:40ants-routes/defroutes
                          #:get)
  (:import-from #:codabrus/frontend/pages/main
                #:make-main-page)
  (:import-from #:codabrus/frontend/routes
                #:diagram-sse-route
                #:stream-sse-route)
  (:export #:app))
(in-package #:codabrus/frontend/app)


(defun make-page-frame (content &key title)
  (declare (ignore title))
  (make-funcall-widget
   (lambda ()
     (with-html ()
       (:div :class "h-screen"
             (render content))))))


(defapp app
  :prefix "/"
  :routes
  ((page ("/" :name "index"
              :title "Codabrus")
     (make-main-page))
    (get ("/diagram-events" :name "diagram-events"
                            :route-class diagram-sse-route))
   (get ("/stream-events" :name "stream-events"
                           :route-class stream-sse-route)))
  :page-constructor #'make-page-frame)
