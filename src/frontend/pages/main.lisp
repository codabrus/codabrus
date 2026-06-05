(uiop:define-package #:codabrus/frontend/pages/main
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
  (:import-from #:codabrus/frontend/widgets/x6-diagram
                #:make-x6-diagram)
  (:import-from #:codabrus/frontend/widgets/prompt-input
                #:make-prompt-input)
  (:import-from #:codabrus/frontend/widgets/thinking-sidebar
                #:make-thinking-sidebar)
  (:export #:make-main-page))
(in-package #:codabrus/frontend/pages/main)


(defwidget main-page (ui-widget)
  ((diagram :initform (make-x6-diagram)
            :reader main-page-diagram)
   (prompt :initform (make-prompt-input)
           :reader main-page-prompt)
   (sidebar :initform (make-thinking-sidebar)
            :reader main-page-sidebar)))


(defun make-main-page ()
  (make-instance 'main-page))


(defmethod render ((widget main-page) (theme tailwind-theme))
  (with-html ()
    (:div :class "flex flex-col h-screen"
          (:div :class "flex flex-1 overflow-hidden"
                (:div :class "flex-1 overflow-auto"
                      (render (main-page-diagram widget) theme))
                (:div :class "w-80 flex-shrink-0 flex flex-col h-full"
                      (:div :class "h-full flex-1 min-h-0"
                            (render (main-page-sidebar widget) theme))))
          (:div :class "border-t border-gray-200 dark:border-gray-700 p-4 bg-white dark:bg-gray-800 flex-shrink-0"
                (render (main-page-prompt widget) theme)))))
