(uiop:define-package #:codabrus/frontend/app
  (:use #:cl)
  (:import-from #:reblocks/app
                #:defapp)
  (:import-from #:reblocks/routes
                #:page)
  (:import-from #:reblocks/widgets/funcall-widget
                #:make-funcall-widget)
  (:import-from #:reblocks/html
                #:with-html)
  (:import-from #:reblocks/widget
                #:render)
  (:import-from #:codabrus/frontend/pages/main
                #:make-main-page)
  (:export #:app))
(in-package #:codabrus/frontend/app)


(defun make-page-frame (content &key title)
  (declare (ignore title))
  (make-funcall-widget
   (lambda ()
     (with-html ()
       (:div :class "flex flex-col gap-8 mx-auto max-w-4xl px-4 my-8"
             (:header :class "text-2xl font-bold"
                      "Codabrus")
             (:div (render content)))))))


(defapp app
  :prefix "/"
  :routes
  ((page ("/" :name "index"
              :title "Codabrus")
     (make-main-page)))
  :page-constructor #'make-page-frame)
