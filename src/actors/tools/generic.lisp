(uiop:define-package #:codabrus/actors/tools/generic
  (:use #:cl)
  (:export #:render-tool-result))
(in-package #:codabrus/actors/tools/generic)


(defgeneric render-tool-result (tool)
  (:documentation "Return a string representation of a tool actor's result, suitable for sending back to the LLM.")
  (:method ((tool t))
    (format nil "~A" tool)))
