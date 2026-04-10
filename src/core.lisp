(uiop:define-package #:codabrus
  (:use #:cl)
  (:import-from #:codabrus/session
                #:make-session
                #:run-session)
  (:nicknames #:codabrus/core))
(in-package #:codabrus)


(defun test-ai (request &optional prev-session)
  "Run REQUEST in a session. If PREV-SESSION is given, continue that conversation.
   Returns the updated session."
  (let* ((project-dir (or (probe-file "~/projects/ai/aider/")
                          (probe-file "~/projects/aider/")
                          (error "Aider folder not found")))
         (session (or prev-session (make-session project-dir))))
    (run-session session request)))
