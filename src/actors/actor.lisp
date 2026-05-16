(uiop:define-package #:codabrus/actors/actor
  (:use #:cl)
  (:export #:stashing-actor))
(in-package #:codabrus/actors/actor)


(defclass stashing-actor (act:actor sento.stash:stashing)
  ())
