(uiop:define-package #:codabrus/tools/edit-file
  (:use #:cl)
  (:import-from #:completions
                #:defun-tool)
  (:import-from #:codabrus/vars
                #:*project-dir*)
  (:import-from #:serapeum
                #:fmt
                #:length<=)
  (:import-from #:cl-ppcre
                #:register-groups-bind)
  (:export #:edit-file))
(in-package #:codabrus/tools/edit-file)


(defun %extract-rejects-filename (text)
  "Extract the rejects filename from patch output text.
Returns the filename as a string or NIL if not found."
  (register-groups-bind (filename)
      ("saving rejects to file\\s+(\\S+)" text)
    filename))


(defun %edit-file (target-file instructions diff-patch)
  (log:info "Editing file"
            target-file
            instructions)
  
  (let ((pathname (merge-pathnames target-file
                                   *project-dir*)))
    (unless (probe-file pathname)
      (alexandria:write-string-into-file "" pathname))
    
    (multiple-value-bind (output error-output exit-code)
        (uiop:with-current-directory (*project-dir*)
          (uiop:run-program (list "patch"
                                  "--posix"
                                  "--no-backup-if-mismatch"
                                  "-p" "1")
                            :input (list diff-patch)
                            :output '(:string :stripped t)
                            :error-output '(:string :stripped t)
                            :ignore-error-status t))
      (cond
        ((zerop exit-code)
         "OK")
        (t
         (let* ((filename (%extract-rejects-filename output))
                (rejected-patch (when filename
                                  (let ((full-filename (merge-pathnames filename
                                                                        *project-dir*)))
                                    (prog1 (alexandria:read-file-into-string full-filename)
                                      (uiop:delete-file-if-exists full-filename)))))
                (result (fmt "Diff command failed with code ~A.~@[~2%It's STDOUT:~2%```~%~A~%```~]~@[~2%It's STDERR:~2%```~%~A~%```~]~@[~2%Rejected patch:~2%```diff~%~A~%```~]"
                             exit-code
                             (unless (str:emptyp output)
                               output)
                             (unless (str:emptyp error-output)
                               error-output)
                             rejected-patch)))
           (log:info "DIFF RESULT" result)
           (values result)))))))


(defun-tool edit-file ((target-file string "The path of the file to edit. You can use either a relative path in the workspace or an absolute path. If an absolute path is provided, it will be preserved as is.")
                       (instructions string "A single sentence instruction describing what should be changed.")
                       (diff-patch string "Specify ONLY the patch lines as show in the tool description. Keep to the unified diff format, this is VERY IMPORTANT."))

  "
Use this tool to propose an edit to an existing file.

You should pass as DIFF-PATCH argument a text in the unified diff format. Keep this format precisely.

An example of unified diff format:

```
diff --git a/aider/utils.py b/aider/utils.py
--- a/aider/utils.py
+++ b/aider/utils.py
@@ -70,7 +70,7 @@
         super().__exit__(exc_type, exc_val, exc_tb)
 
 
-def make_repo(path=None):
+def make_repo(path=None, repo_name=None):
     import git
 
     if not path:
```

IT IS IMPORTANT TO USE `a` and `b` prefixes to the filenames, like:

```
--- a/aider/utils.py
+++ b/aider/utils.py
```

If you omit it, diff command will fail.

"

  (let ((response (%edit-file target-file
                              instructions
                              diff-patch)))
    (values response)))
