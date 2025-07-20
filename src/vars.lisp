(uiop:define-package #:codabrus/vars
  (:use #:cl)
  (:import-from #:serapeum
                #:defvar-unbound)
  (:export #:*project-dir*))
(in-package #:codabrus/vars)


(defvar-unbound *project-dir*
  "An absolute path to the root directory of the current project.")
