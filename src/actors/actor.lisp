(uiop:define-package #:codabrus/actors/actor
  (:use #:cl)
  (:import-from #:sento.actor)
  (:export #:stashing-actor))
(in-package #:codabrus/actors/actor)


(defclass stashing-actor (act:actor sento.stash:stashing)
  ())
