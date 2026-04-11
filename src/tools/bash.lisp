(uiop:define-package #:codabrus/tools/bash
  (:use #:cl)
  (:import-from #:completions
                #:defun-tool)
  (:import-from #:codabrus/vars
                #:*project-dir*
                #:*headless-mode*
                #:*allow-execute*
                #:headless-permission-denied)
  (:import-from #:serapeum
                #:fmt)
  (:import-from #:bordeaux-threads
                #:make-thread)
  (:import-from #:log)
  (:export #:bash))
(in-package #:codabrus/tools/bash)


(defparameter *output-limit* 4000
  "Maximum number of output characters returned to the agent.")

(defparameter *default-timeout* 30
  "Default command timeout in seconds.")


(defun %bash (command &key (timeout *default-timeout*))
  (when (and *headless-mode* (not *allow-execute*))
    (log:warn "Bash tool denied in headless mode (pass --allow-execute to enable)")
    (error 'headless-permission-denied :tool-name "bash"))
  (log:info "Running bash command" command)
  (handler-case
      (let* ((timed-out nil)
             (process (uiop:launch-program
                       (list "sh" "-c" command)
                       :output :stream
                       :error-output :output
                       :directory *project-dir*)))
        ;; Watcher thread: marks timeout and kills the process after the deadline.
        ;; Flag is set before killing so the main thread always sees it by the
        ;; time uiop:wait-process returns.
        (make-thread
         (let ((p process))
           (lambda ()
             (sleep timeout)
             (when (uiop:process-alive-p p)
               (setf timed-out t)
               (uiop:terminate-process p :urgent t))))
         :name "bash-timeout-watcher")
        (let* ((raw (uiop:slurp-stream-string
                     (uiop:process-info-output process)))
               (exit-code (uiop:wait-process process))
               (output (if (> (length raw) *output-limit*)
                           (fmt "~A~%... [truncated, ~A chars total]"
                                (subseq raw 0 *output-limit*)
                                (length raw))
                           raw)))
          (cond
            (timed-out
             (fmt "Command timed out after ~A seconds.~%~A" timeout output))
            ((zerop exit-code)
             (if (str:emptyp output) "(no output)" output))
            (t
             (fmt "Exit ~A~%~A" exit-code output)))))
    (error (e)
      (fmt "Error running command: ~A" e))))


(defun-tool bash ((command string "The shell command to execute. Runs via sh -c.")
                  (explanation string "One sentence explaining why this command is needed."))
  "Execute a shell command in the project directory and return its output.

stdout and stderr are merged. Non-zero exit codes are reported in the output.
Output is capped at 4000 characters; if the command produces more, the output
is truncated and the total length is reported.
Commands that run longer than 30 seconds are killed and reported as timed out.

Use this tool to:
- Run the project test suite (e.g. \"make test\", \"cargo test\", \"rove\")
- Check git status or diff
- Compile or build the project
- Inspect the environment (e.g. \"ls\", \"which sbcl\")

Do NOT use this tool to modify files — prefer edit-file for that."
  (declare (ignore explanation))
  (%bash command))
