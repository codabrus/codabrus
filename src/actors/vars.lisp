(uiop:define-package #:codabrus/actors/vars
  (:use #:cl)
  (:export #:*actor-system*))
(in-package #:codabrus/actors/vars)


(defvar *actor-system* nil
  "The global Sento actor-system instance. Bound by START-ACTOR-SYSTEM.")

