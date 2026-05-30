(uiop:define-package #:codabrus/frontend/widgets/x6-diagram
  (:use #:cl)
  (:import-from #:reblocks/widget
                #:defwidget)
  (:import-from #:reblocks-ui2/widget
                #:render
                #:ui-widget
                #:get-dependencies)
  (:import-from #:reblocks-ui2/themes/tailwind
                #:tailwind-theme)
  (:import-from #:reblocks/dependencies
                #:make-dependency)
  (:import-from #:reblocks/html
                #:with-html)
  (:import-from #:reblocks/widgets/dom
                #:dom-id)
  (:import-from #:parenscript
                #:ps
                #:chain)
  (:export #:make-x6-diagram))
(in-package #:codabrus/frontend/widgets/x6-diagram)


(defwidget x6-diagram (ui-widget)
  ())


(defun make-x6-diagram ()
  (make-instance 'x6-diagram))


(defmethod get-dependencies ((widget x6-diagram) (theme tailwind-theme))
  (list (make-dependency "src/frontend/x6/build/diagram.js"
                          :system :codabrus)))


(defun %make-init-js (container-id)
  (ps:ps
    (let ((container (ps:chain document (get-element-by-id (ps:lisp container-id)))))
      (when (and container
                 (typeof (ps:@ window init-diagram)))
        (let ((graph (ps:chain window (init-diagram (ps:lisp container-id)
                                                     (ps:create
                                                      nodes (array
                                                             (ps:create id "n1" x 80 y 80 width 100 height 40 label "Hello")
                                                             (ps:create id "n2" x 280 y 180 width 100 height 40 label "World"))
                                                      edges (array
                                                             (ps:create source "n1" target "n2")))))))
          (setf (ps:@ window codabrus-graph) graph)
          (let ((es (ps:new (-event-source "/diagram-events"))))
            (ps:chain es
                      (add-event-listener "add-node"
                                          (lambda (event)
                                            (let ((data (ps:chain -j-s-o-n (parse (ps:@ event data)))))
                                              (when graph
                                                (ps:chain graph (add-node
                                                                 (ps:create
                                                                  id (ps:@ data id)
                                                                  x (ps:@ data x)
                                                                  y (ps:@ data y)
                                                                  width (ps:@ data width)
                                                                  height (ps:@ data height)
                                                                  label (ps:@ data label))))
                                                (when (ps:@ data source)
                                                  (ps:chain graph (add-edge
                                                                   (ps:create
                                                                    source (ps:@ data source)
                                                                    target (ps:@ data id))))))))))
            (ps:chain es
                      (add-event-listener "error"
                                          (lambda ()
                                            (ps:chain console (log "SSE connection error")))))))))))


(defmethod render ((widget x6-diagram) (theme tailwind-theme))
  (let ((container-id (dom-id widget)))
    (with-html ()
      (:div :id container-id
            :style "width: 100%; height: 600px;"))
    (with-html ()
      (:script :type "text/javascript"
               (:raw (%make-init-js container-id))))))
