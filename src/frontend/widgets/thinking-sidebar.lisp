(uiop:define-package #:codabrus/frontend/widgets/thinking-sidebar
  (:use #:cl)
  (:import-from #:reblocks/widget
                #:defwidget)
  (:import-from #:reblocks-ui2/widget
                #:render
                #:ui-widget)
  (:import-from #:reblocks-ui2/themes/tailwind
                #:tailwind-theme)
  (:import-from #:reblocks/html
                #:with-html)
  (:import-from #:reblocks/widgets/dom
                #:dom-id)
  (:export #:make-thinking-sidebar))
(in-package #:codabrus/frontend/widgets/thinking-sidebar)


(defwidget thinking-sidebar (ui-widget)
  ())


(defun make-thinking-sidebar ()
  (make-instance 'thinking-sidebar))


(defmethod render ((widget thinking-sidebar) (theme tailwind-theme))
  (let ((container-id (format nil "~A-content" (dom-id widget))))
    (with-html ()
      (:div :class "flex flex-col h-full bg-gray-900 border-l border-gray-700"
            (:div :class "px-4 py-3 border-b border-gray-700 flex items-center justify-between"
                  (:h2 :class "text-sm font-semibold text-gray-300"
                       "Thinking")
                  (:span :id (format nil "~A-status" container-id)
                         :class "text-xs text-gray-500"
                         ""))
            (:div :id container-id
                  :class "flex-1 overflow-y-auto p-4 font-mono text-sm text-gray-200 whitespace-pre-wrap break-words"))
      (:script :type "text/javascript"
               (:raw (%make-sidebar-js container-id))))))


(defun %make-sidebar-js (container-id)
  (format nil "(function() {
  var containerId = '~A';
  var container = document.getElementById(containerId);
  if (!container) return;
  var autoScroll = true;
  container.addEventListener('scroll', function() {
    autoScroll = (container.scrollTop + container.clientHeight >= container.scrollHeight - 4);
  });
  if (window._codabrusStreamES) { window._codabrusStreamES.close(); }
  var es = new EventSource('/stream-events');
  window._codabrusStreamES = es;
  var statusEl = document.getElementById(containerId + '-status');
  es.addEventListener('stream-chunk', function(event) {
    var text = event.data.replace(/\\\\n/g, '\\n').replace(/\\\\\\\\/g, '\\\\');
    container.appendChild(document.createTextNode(text));
    if (autoScroll) container.scrollTop = container.scrollHeight;
    if (statusEl) statusEl.textContent = 'thinking...';
  });
  es.addEventListener('stream-done', function() {
    if (statusEl) statusEl.textContent = 'done';
  });
  es.addEventListener('stream-clear', function() {
    container.textContent = '';
    autoScroll = true;
    if (statusEl) statusEl.textContent = '';
  });
  es.addEventListener('error', function() {
    console.log('Stream SSE connection error');
  });
})();"
          container-id))
