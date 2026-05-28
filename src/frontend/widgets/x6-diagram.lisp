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
  (:export #:make-x6-diagram))
(in-package #:codabrus/frontend/widgets/x6-diagram)


(defwidget x6-diagram (ui-widget)
  ())


(defun make-x6-diagram ()
  (make-instance 'x6-diagram))


(defmethod get-dependencies ((widget x6-diagram) (theme tailwind-theme))
  (list (make-dependency "src/frontend/x6/build/diagram.js"
                          :system :codabrus)))


(defmethod render ((widget x6-diagram) (theme tailwind-theme))
  (let ((container-id (dom-id widget)))
    (with-html ()
      (:div :id container-id
            :style "width: 100%; height: 600px;"))
    (with-html ()
      (:script :type "text/javascript"
               (:raw 
                (format nil
                        "document.addEventListener('DOMContentLoaded', function() { ~
                          if (typeof initDiagram === 'function') { ~
                            initDiagram('~A', { ~
                              nodes: [~
                                {id: 'n1', x: 80, y: 80, width: 100, height: 40, label: 'Hello'}, ~
                                {id: 'n2', x: 280, y: 180, width: 100, height: 40, label: 'World'} ~
                              ], ~
                              edges: [~
                                {source: 'n1', target: 'n2'} ~
                              ] ~
                            }); ~
                          } ~
                        });"
                        container-id))))))
