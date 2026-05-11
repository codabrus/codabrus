(uiop:define-package #:codabrus/actors/tools/bash
  (:use #:cl)
  (:import-from #:codabrus/actors/generic
                #:process-message
                #:make-clos-actor))
(in-package #:codabrus/actors/tools/bash)


(defclass bash ()
  ((command :type string
            :initarg :command
            :reader bash-command)
   (stdout :type array
           :initform (make-array 0
                                 :element-type 'string
                                 :adjustable t
                                 :fill-pointer 0)
           :reader bash-stdout)
   (stderr :type array
           :initform (make-array 0
                                 :element-type 'string
                                 :adjustable t
                                 :fill-pointer 0)
           :reader bash-stderr)
   (exit-code :type (or null integer)
              :initform nil
              :reader bash-exit-code)))


(defmethod print-object ((obj bash) stream)
  (print-unreadable-object (obj stream :type t)
    (format stream "~S :exit-code ~A~@[ :stdout ~A~]~@[ :stderr ~A~]"
            (bash-command obj)
            (bash-exit-code obj)
            (let ((len (length (bash-stdout obj))))
              (when (plusp len) len))
            (let ((len (length (bash-stderr obj))))
              (when (plusp len) len)))))


(defun make-bash (command)
  (make-clos-actor 'bash
                   :command command))


(defun run-async (command &key on-stdout-line on-stderr-line on-exit)
  (let* ((process (uiop:launch-program command 
                                       :output :stream 
                                       :error-output :stream))
         (out (uiop:process-info-output process))
         (err (uiop:process-info-error-output process)))
    (loop with out-buffer = (make-string-output-stream)
          with err-buffer = (make-string-output-stream)
          do ;; Non-blocking read from stdout
             (loop for char = (read-char-no-hang out nil :eof)
                   while (and char (not (eq char :eof)))
                   do (write-char char out-buffer)
                   when (char= char #\newline)
                     do (when on-stdout-line
                          (funcall on-stdout-line
                                   (get-output-stream-string out-buffer))) ; process line
                        (setf out-buffer (make-string-output-stream)))
             ;; similarly for stderr
             (loop for char = (read-char-no-hang err nil :eof)
                   while (and char (not (eq char :eof)))
                   do (write-char char err-buffer)
                   when (char= char #\newline)
                     do (when on-stderr-line
                          (funcall on-stderr-line (get-output-stream-string err-buffer)))
                        (setf err-buffer (make-string-output-stream)))
             
             (when (not (uiop:process-alive-p process))
               ;; process done, but check if there's remaining data (flush buffers after loop)
               (loop for char = (read-char-no-hang out nil :eof)
                     while (and char (not (eq char :eof)))
                     do (write-char char out-buffer))
               (loop for char = (read-char-no-hang err nil :eof)
                     while (and char (not (eq char :eof)))
                     do (write-char char err-buffer))
               ;; print any remaining partial lines
               (let ((rem-out (get-output-stream-string out-buffer)))
                 (when (and on-stdout-line
                            (plusp (length rem-out)))
                   (funcall on-stdout-line rem-out)))
               (let ((rem-err (get-output-stream-string err-buffer)))
                 (when (and on-stderr-line
                            (plusp (length rem-err)))
                   (funcall on-stderr-line rem-err)))
               ;; (log:info "Exiting from the loop")
               (return))
             ;; possibly do other work or sleep to avoid busy-loop
             ;; (log:info "Going to sleep")
             (sleep 0.5))
    ;; finally get exit code
    (when on-exit
      ;; (log:info "Calling on exit")
      (let ((code (uiop:wait-process process)))
        ;; (log:info "Exit code is" code)
        (funcall on-exit code)))))


(defmethod process-message ((obj bash) (message (eql :run)) &key)
  (let ((command (bash-command obj)))
    (log:info "Running command" command)
           
    (tasks:with-context (act:*self*)
      (let ((caller act:*self*))
        ;; (act:become (make-shell-runner-waiting))
        (sento.tasks:task-async
         (lambda ()
           (run-async command
                      :on-stdout-line (lambda (line)
                                        (act:ask caller (list :on-stdout :line line)))
                      :on-stderr-line (lambda (line)
                                        (act:ask caller (list :on-stderr :line line)))
                      :on-exit (lambda (code)
                                 (act:ask caller (list :on-exit :code code))))))))))


(defmethod process-message ((obj bash) (message (eql :on-stdout)) &key line)
  (vector-push-extend line (bash-stdout obj)))

(defmethod process-message ((obj bash) (message (eql :on-stderr)) &key line)
  (vector-push-extend line (bash-stderr obj)))

(defmethod process-message ((obj bash) (message (eql :on-exit)) &key code)
  (setf (slot-value obj 'exit-code)
        code))

(defmethod process-message ((obj bash) (message (eql :is-finished)) &key)
  (when (bash-exit-code obj)
    t))
