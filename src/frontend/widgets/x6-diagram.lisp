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
  (:import-from #:reblocks/actions
                #:make-js-action)
  (:import-from #:parenscript
                #:ps
                #:chain)
  (:import-from #:codabrus/frontend/widgets/message-popup
                #:message-popup
                #:make-message-popup
                #:show-node-popup)
  (:export #:make-x6-diagram))
(in-package #:codabrus/frontend/widgets/x6-diagram)


(defwidget x6-diagram (ui-widget)
  ((popup :initform (make-message-popup)
          :reader x6-diagram-popup)))


(defun make-x6-diagram ()
  (make-instance 'x6-diagram))


(defmethod get-dependencies ((widget x6-diagram) (theme tailwind-theme))
  (list (make-dependency "src/frontend/x6/build/diagram.js"
                          :system :codabrus)))


(defun %make-on-node-click-js (popup-widget)
  (make-js-action
   (lambda (&key node-id &allow-other-keys)
     (show-node-popup popup-widget node-id))
   :args (serapeum:dict "node-id" '(ps:chain event node id))))


(defun %make-init-js (container-id popup-widget)
  (let ((on-node-click-js (%make-on-node-click-js popup-widget)))
    (ps:ps
      (let ((container (ps:chain document (get-element-by-id (ps:lisp container-id)))))
        (when (and container
                   (typeof (ps:@ window init-diagram)))
          (let ((graph (ps:chain window (init-diagram (ps:lisp container-id)
                                                       (ps:create)))))
            (setf (ps:@ window codabrus-graph) graph)
            (ps:chain graph (on "node:click"
                                (lambda (args)
                                  (let ((event (ps:@ args e))
                                        (node (ps:@ args node)))
                                    (ps:lisp on-node-click-js)))))
            (let ((es (ps:new (-event-source "/diagram-events"))))
              (ps:chain es
                        (add-event-listener "init-diagram"
                                            (lambda (event)
                                              (let ((data (ps:chain -j-s-o-n (parse (ps:@ event data)))))
                                                (when graph
                                                  (ps:chain graph (clear-cells))
                                                  (let ((nodes (ps:@ data nodes)))
                                                    (ps:chain nodes
                                                              (for-each
                                                               (lambda (n)
                                                                 (ps:chain graph (add-node n))))))
                                                  (let ((edges (ps:@ data edges)))
                                                    (ps:chain edges
                                                              (for-each
                                                               (lambda (e)
                                                                 (ps:chain graph (add-edge e)))))))))))
              (ps:chain es
                        (add-event-listener "error"
                                            (lambda ()
                                              (ps:chain console (log "SSE connection error"))))))))))))


(defmethod render ((widget x6-diagram) (theme tailwind-theme))
  (let ((container-id (dom-id widget))
        (popup (x6-diagram-popup widget)))
    (with-html ()
      (:div :id container-id
            :style "width: 100%; height: 600px;")
      (render popup theme)
      (:script :type "text/javascript"
               (:raw (%make-init-js container-id popup))))))
