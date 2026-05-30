(uiop:define-package #:codabrus/frontend/widgets/prompt-input
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
                #:make-js-form-action
                #:make-js-action)
  (:import-from #:codabrus/frontend/diagram/session
                #:send-user-message
                #:agent-free-p
                #:reset-session)
  (:export #:make-prompt-input))
(in-package #:codabrus/frontend/widgets/prompt-input)


(defwidget prompt-input (ui-widget)
  ())


(defun make-prompt-input ()
  (make-instance 'prompt-input))


(defmethod render ((widget prompt-input) (theme tailwind-theme))
  (let ((submit-action (make-js-form-action
                        (lambda (&key message &allow-other-keys)
                          (when (and message (string/= message ""))
                            (send-user-message message)))))
        (reset-action (make-js-action
                       (lambda (&key &allow-other-keys)
                         (reset-session)))))
    (with-html ()
      (:form :class "flex gap-2 w-full"
             :onsubmit (format nil "~A; return false;" submit-action)
             (:input :type "text"
                     :name "message"
                     :placeholder "Ask Codabrus..."
                     :class "flex-1 px-4 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500 dark:bg-gray-700 dark:border-gray-600 dark:text-white"
                     :autocomplete "off")
             (:button :type "submit"
                      :class "px-6 py-2 bg-blue-500 text-white rounded-lg hover:bg-blue-600 font-semibold"
                      "Send")
             (:button :type "button"
                      :class "px-6 py-2 bg-red-500 text-white rounded-lg hover:bg-red-600 font-semibold"
                      :onclick reset-action
                      "Reset")))))
