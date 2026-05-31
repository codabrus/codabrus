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
  (:import-from #:yason
                #:parse)
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


(defun safe-parse-json (str)
  (when (and str (stringp str) (plusp (length str)))
    (handler-case (yason:parse str)
      (error () nil))))


(defun shallow-copy-hash-table (ht)
  (let ((copy (make-hash-table :test (hash-table-test ht))))
    (maphash (lambda (k v) (setf (gethash k copy) v)) ht)
    copy))


(defun args-without-explanation (parsed-args)
  (when parsed-args
               (let ((copy (shallow-copy-hash-table parsed-args)))
      (remhash "explanation" copy)
      copy)))


(defun render-bash-call (parsed-args)
  (let ((command (gethash "command" parsed-args)))
    (with-html ()
      (:div :class "mb-2"
            (:span :class "text-xs text-gray-400" "command")
            (:br)
            (:code :class "text-sm text-green-300 bg-gray-900 rounded px-2 py-1 font-mono"
                   (or command ""))))))


(defun render-generic-call (tool-name parsed-args)
  (declare (ignore tool-name))
  (with-html ()
    (:pre :class "text-sm text-gray-800 dark:text-gray-200 whitespace-pre-wrap break-words bg-gray-50 dark:bg-gray-900 rounded p-2"
          (let ((copy (shallow-copy-hash-table parsed-args)))
            (remhash "explanation" copy)
            (if (plusp (hash-table-count copy))
                (with-output-to-string (s)
                  (yason:encode copy s))
                "")))))


(defun render-tool-call (tool-name parsed-args)
  (cond
    ((string-equal tool-name "bash")
     (render-bash-call parsed-args))
    (t
     (render-generic-call tool-name parsed-args))))


(defun render-tool-section (data)
  (let* ((tool-name (gethash "tool-name" data))
         (raw-args (gethash "tool-args" data))
         (parsed (safe-parse-json raw-args))
         (explanation (and parsed (gethash "explanation" parsed))))
    (with-html ()
      (:div :class "mb-3 pb-3 border-b border-gray-200 dark:border-gray-600"
            (when explanation
              (with-html ()
                (:p :class "text-sm text-gray-600 dark:text-gray-300 italic mb-2"
                    explanation)))
            (:div :class "text-xs font-semibold text-gray-500 dark:text-gray-400 uppercase mb-2"
                  "Call")
            (if parsed
                (render-tool-call tool-name parsed)
                (with-html ()
                  (:pre :class "text-sm text-gray-800 dark:text-gray-200 whitespace-pre-wrap break-words bg-gray-50 dark:bg-gray-900 rounded p-2"
                        (or raw-args ""))))))))


(defun render-content-section (role content)
  (with-html ()
    (when (string= role "tool")
      (with-html ()
        (:div :class "text-xs font-semibold text-gray-500 dark:text-gray-400 uppercase mb-1"
              "Result")))
    (:pre :class "text-sm text-gray-800 dark:text-gray-200 whitespace-pre-wrap break-words"
          (or content ""))))


(defmethod render ((widget message-popup) (theme tailwind-theme))
  (if (popup-visible-p widget)
      (let* ((data (popup-node-data widget))
             (role (gethash "role" data))
             (content (gethash "content" data))
             (hide-js (make-js-action
                       (lambda (&key &allow-other-keys)
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
                                     (:raw "&#215;")))
                      (:div :class "overflow-auto max-h-96"
                             (when (string= role "tool")
                               (render-tool-section data))
                            (render-content-section role content))))))
      (with-html ()
        (:div :style "display:none"))))
