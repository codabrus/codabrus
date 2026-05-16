(uiop:define-package #:codabrus/actors/callbacks
  (:use #:cl)
  (:import-from #:codabrus/actors/vars
                #:*actor-system*)
  (:export #:call-callback
           #:callback-type))
(in-package #:codabrus/actors/callbacks)


(deftype callback-type ()
  '(or null sento.actor:actor string symbol function))


(defun resolve-callback (callback)
  (etypecase callback
    (sento.actor:actor callback)
    (string (first (ac:find-actors *actor-system* callback)))
    (symbol (if (fboundp callback)
                (symbol-function callback)
                (error "Symbol ~S is not fbound" callback)))
    (function callback)))


(defun call-callback (callback message &rest args-plist)
  (let ((resolved (resolve-callback callback)))
    (etypecase resolved
      (sento.actor:actor
         (act:ask resolved (list* message args-plist)))
      (function
         (apply resolved message args-plist)))))
