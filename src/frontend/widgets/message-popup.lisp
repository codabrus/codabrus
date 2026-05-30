(uiop:define-package #:codabrus/frontend/widgets/message-popup
  (:use #:cl)
  (:import-from #:reblocks/widget
                #:defwidget
                #:update)
  (:import-from #:reblocks-ui2/widget
                #:render
                #:ui-widget)
  (:import-from #:reblocks-ui2/themes/tailwind
                #:tailwind-theme)
  (:import-from #:reblocks/html
                #:with-html)
  (:import-from #:reblocks/actions
                #:make-js-action)
  (:import-from #:codabrus/frontend/diagram/builder
                #:get-node-data)
  (:export #:message-popup
           #:make-message-popup
           #:show-node-popup
           #:hide-popup
           #:popup-visible-p))
(in-package #:codabrus/frontend/widgets/message-popup)


(defwidget message-popup (ui-widget)
  ((visible :initform nil
            :accessor popup-visible-p)
   (node-data :initform nil
              :accessor popup-node-data)))


(defun make-message-popup ()
  (make-instance 'message-popup))


(defun role-badge-class (role)
  (cond
    ((string= role "system") "bg-gray-500")
    ((string= role "user") "bg-blue-500")
    ((string= role "assistant") "bg-green-500")
    ((string= role "tool") "bg-amber-500")
    (t "bg-gray-400")))


(defun show-node-popup (popup node-id)
  (let ((data (get-node-data node-id)))
    (when data
      (setf (popup-node-data popup) data
            (popup-visible-p popup) t)
      (update popup))))


(defun hide-popup (popup)
  (setf (popup-visible-p popup) nil)
  (update popup))


(defmethod render ((widget message-popup) (theme tailwind-theme))
  (when (popup-visible-p widget)
    (let* ((data (popup-node-data widget))
           (role (gethash "role" data))
           (content (gethash "content" data))
           (hide-js (make-js-action (lambda (&key &allow-other-keys)
                                      (hide-popup widget)))))
      (with-html ()
        (:div :class "fixed inset-0 bg-black/50 flex items-center justify-center z-50"
              :onclick hide-js
              (:div :class "bg-white dark:bg-gray-800 rounded-lg shadow-xl max-w-lg w-full p-6"
                    :onclick "event.stopPropagation()"
                    (:div :class "flex items-center justify-between mb-4"
                          (:span :class (format nil "px-2 py-1 rounded text-xs text-white font-semibold ~A"
                                                (role-badge-class role))
                                 (string-capitalize role))
                          (:button :class "text-gray-500 hover:text-gray-700 text-xl font-bold"
                                   :onclick hide-js
                                   "&#215;"))
                    (:div :class "overflow-auto max-h-96"
                          (:pre :class "text-sm text-gray-800 dark:text-gray-200 whitespace-pre-wrap break-words"
                                (or content "")))))))))
