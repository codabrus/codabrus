(uiop:define-package #:codabrus/playground
  (:use #:cl))
(in-package #:codabrus/playground)


(defvar *sys* nil)


(defun ensure-sys ()
  (unless *sys*
    (setf *sys*
          (asys:make-actor-system)))
  *sys*)


(defun test-task ()
  (ensure-sys)
  (tasks:with-context (*sys*)
    (tasks:task-start (lambda ()
                        (log:error "RUNNING TASK")
                        (+ 1 1)))))

(defun test-async-task1 ()
  (ensure-sys)
  (tasks:with-context (*sys*)
    (tasks:task-async (lambda ()
                        (log:error "RUNNING TASK")
                        (+ 1 1))
                      :on-complete-fun (lambda (result)
                                         (log:error "TASK is Done" result)))))


(defun test-async-stream-task ()
  (ensure-sys)
  (tasks:with-context (*sys*)
    (sento.tasks:task-async-stream
     (lambda (val)
       (log:info "RUNNING TASK" val)
       (* val val))
     (list 1 2 3 4 5))))


(defun show-user-actors ()
  (sento.actor-context:all-actors *sys*))


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



(defun make-shell-runner-waiting ()
  ;; (log:info "Received" message)

  (let ((stdout nil)
        (stderr nil))
    (lambda (message)
      (let ((method (car message)))

        (ecase method
          ;; (:run
          ;;    (let ((command (second message)))
          ;;      (log:info "Running command" command)
         
          ;;      (tasks:with-context (act:*self*)
          ;;        (let ((caller act:*self*))
          ;;          (sento.tasks:task-async
          ;;           (lambda ()
          ;;             (run-async command
          ;;                        :on-stdout-line (lambda (line)
          ;;                                          (act:ask caller (list :on-stdout line)))
          ;;                        :on-stderr-line (lambda (line)
          ;;                                          (act:ask caller (list :on-stderr line)))
          ;;                        :on-exit (lambda (code)
          ;;                                   (act:ask caller (list :on-exit code))))))))))
          (:on-stdout
             (let ((line (second message)))
               ;; (log:info "STDOUT: ~A" line)
               (push line stdout)))
          (:on-stderr
             (let ((line (second message)))
               ;; (log:info "STDERR: ~A" line)
               (push line stderr)))
          (:on-exit
             (let ((code (second message)))
               (when stdout
                 (log:info "STDOUT:~%~A" (str:join "" (reverse stdout))))
               (when stderr
                 (log:info "STDERR:~%~A" (str:join "" (reverse stderr))))
               (log:info "EXIT: ~A" code)
               (act:unbecome))))))))


(defun shell-runner-receive (message)
  ;; (log:info "Received" message)

  (let ((method (car message)))

    (ecase method
      (:run
         (let ((command (second message)))
           (log:info "Running command" command)
           
           (tasks:with-context (act:*self*)
             (let ((caller act:*self*))
               (act:become (make-shell-runner-waiting))
               (sento.tasks:task-async
                (lambda ()
                  (run-async command
                             :on-stdout-line (lambda (line)
                                               (act:ask caller (list :on-stdout line)))
                             :on-stderr-line (lambda (line)
                                               (act:ask caller (list :on-stderr line)))
                             :on-exit (lambda (code)
                                        (act:ask caller (list :on-exit code))))))))))
      ;; (:on-stdout
      ;;    (let ((line (second message)))
      ;;      (log:info "STDOUT: ~A" line)))
      ;; (:on-stderr
      ;;    (let ((line (second message)))
      ;;      (log:info "STDERR: ~A" line)))
      ;; (:on-exit
      ;;    (let ((code (second message)))
      ;;      (log:info "EXIT: ~A" code)))
      )))


(defun make-runner ()
  (ac:actor-of *sys*
               :name "shell-runner2"
               :receive (lambda (msg)
                          (shell-runner-receive msg))))


(defparameter *runner* (make-runner))


(defun run (command)
  (act:ask-s *runner*
             (list :run command)))




















;;;; Playing with CLOS and actors

;; (defclass foo ()
;;   ())

;; (defclass bar ()
;;   ())


;; (defgeneric process-message (obj name &key &allow-other-keys)
;;   ;; Foo methods
;;   (:method ((obj foo) (name (eql :hello)) &key)
;;     (log:info "Hello from Foo!"))
  
;;   (:method ((obj foo) (name (eql :become)) &key)
;;     (setf act:*state*
;;           (make-instance 'bar)))


;;   ;; Bar methods

;;   (:method ((obj bar) (name (eql :hello)) &key)
;;     (log:info "Hello from Bar!"))
  
;;   (:method ((obj bar) (name (eql :become)) &key)
;;     (setf act:*state*
;;           (make-instance 'foo))))


(defun make-foo-actor ()
  (ac:actor-of *sys*
               :receive (lambda (message)
                          (apply #'process-message
                                 act:*state*
                                 (uiop:ensure-list message)))
               :state (make-instance 'foo)))




(defun make-interruptable-actor-loop-example ()
  (ac:actor-of *sys*
               :destroy (lambda (&rest args)
                          ;; По сообщению :stop актор будет полностью
                          ;; остановлен и его нельзя будет запустить ещё раз
                          (log:info "Destroy called with ARGS = ~A" args))
               :receive (let ((stopped nil))
                          (lambda (message)
                            (log:info "Processing" message)
                            (case message
                              ;; Но с помощью :break итерацию можно приостановить,
                              ;; а потом продолжить заново с помощью :run.
                              (:break
                                 (log:info "Stopping")
                                 (setf stopped t))
                              (:run
                                 (log:info "Running")
                                 (setf stopped nil)
                                 (act:tell act:*self* :next-iteration))
                              (t
                                 (unless stopped
                                   (log:info "Sleeping")
                                   (sleep 3)
                                   (log:info "Going to next iteration")
                                   (act:tell act:*self* :next-iteration))))))))
