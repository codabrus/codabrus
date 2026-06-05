(uiop:define-package #:codabrus/frontend/server
  (:use #:cl)
  (:import-from #:reblocks/server)
  (:import-from #:reblocks-ui2/themes/api
                #:current-theme)
  (:import-from #:reblocks-ui2/themes/tailwind
                #:make-tailwind-theme)
  (:import-from #:codabrus/frontend/app
                #:app)
  (:import-from #:log)
  (:export #:start
           #:stop))
(in-package #:codabrus/frontend/server)


(defvar *default-port* 8000)
(defvar *default-interface* "localhost")

(defvar *running-on-port* nil)
(defvar *running-on-interface* "localhost")


(defun start (&key
              (port (or *running-on-port*
                        *default-port*))
              (interface (or *running-on-interface*
                             *default-interface*))
              (debug t))
  (setf *running-on-port*
        port)
  (setf *running-on-interface*
        interface)
  (setf (current-theme)
        (make-tailwind-theme))
  (log:info "Starting Codabrus Web UI on ~A:~A" interface port)
  (reblocks/server:start :port port
                         :interface interface
                         :apps '(app)
                         :server-type :hunchentoot
                         :debug debug))


(defun stop ()
  (when *running-on-port*
    (reblocks/server:stop *running-on-interface*
                          *running-on-port*)))
