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
   :args (serapeum:dict "node-id" '(ps:chain node-id))))


(defun %make-init-js (container-id popup-widget)
  (let ((on-node-click-js (%make-on-node-click-js popup-widget)))
    (format nil "(function() {
  var container = document.getElementById('~A');
  if (container && typeof window.initDiagram !== 'undefined') {
    var graph = window.initDiagram('~A', {});
    window.codabrusGraph = graph;
    graph.on('node:click', function(args) {
      var nodeId = args.node.id;
      ~A
    });
    var es = new EventSource('/diagram-events');
    es.addEventListener('init-diagram', function(event) {
      var data = JSON.parse(event.data);
      if (graph) {
        graph.clearCells();
        data.nodes.forEach(function(n) { graph.addNode(n); });
        data.edges.forEach(function(e) { graph.addEdge(e); });
      }
    });
    es.addEventListener('error', function() {
      console.log('SSE connection error');
    });
  }
})();"
            container-id container-id on-node-click-js)))


(defmethod render ((widget x6-diagram) (theme tailwind-theme))
  (let ((container-id (format nil "~A-diagram"
                              (dom-id widget)))
        (popup (x6-diagram-popup widget)))
    (with-html ()
      (:div :id container-id
            :style "width: 100%; height: 600px;")
      (render popup theme)
      (:script :type "text/javascript"
               (:raw (%make-init-js container-id popup))))))
