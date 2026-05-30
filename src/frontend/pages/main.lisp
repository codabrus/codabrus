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
  (:export #:make-main-page))
(in-package #:codabrus/frontend/pages/main)


(defwidget main-page (ui-widget)
  ())


(defun make-main-page ()
  (make-instance 'main-page))


(defmethod render ((widget main-page) (theme tailwind-theme))
  (with-html ()
    (:div :class "flex flex-col items-center justify-center min-h-screen"
          (:h1 :class "text-6xl font-bold"
               "Codabrus")
          (:p :class "mt-4 text-xl text-gray-600"
              "Hackable AI Code Assistant")
          (:div :class "mt-8 w-full"
                (render (make-x6-diagram) theme)))))
