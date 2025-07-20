(uiop:define-package #:codabrus/tools/read-file
  (:use #:cl)
  (:import-from #:completions
                #:defun-tool)
  (:import-from #:codabrus/vars
                #:*project-dir*)
  (:import-from #:serapeum
                #:fmt
                #:length<=)
  (:export
   #:read-file))
(in-package #:codabrus/tools/read-file)


(defun %read-file (target-file
                   start-line-one-indexed-inclusive
                   end-line-one-indexed-inclusive
                   should-read-entire-file 
                   explanation)
  (declare (ignore explanation))
  (log:info "Reading file"
            target-file
            start-line-one-indexed-inclusive
            end-line-one-indexed-inclusive
            should-read-entire-file)
  
  (let ((pathname (probe-file
                   (merge-pathnames target-file
                                    *project-dir*))))
    (cond
      (pathname
       (let* ((lines (uiop:read-file-lines pathname))
              (num-lines (length lines))
              (result
                (cond
                  (should-read-entire-file
                   (fmt "<full-file-content filename=~A>~%~A~%</full-file-content>"
                        target-file
                        (str:join #\Newline lines)))
                  ((= num-lines 0)
                   (fmt "File ~A is EMPTY"
                        target-file))
                  ((< start-line-one-indexed-inclusive 1)
                   "Argument start-line-one-indexed-inclusive should be >= 1")
                  ((> start-line-one-indexed-inclusive num-lines)
                   (fmt "Argument start-line-one-indexed-inclusive should be <= ~A"
                        num-lines))
                  ((> end-line-one-indexed-inclusive num-lines)
                   (fmt "Argument end-line-one-indexed should be <= ~A"
                        num-lines))
                  ((> start-line-one-indexed-inclusive end-line-one-indexed-inclusive)
                   "Argument start-line-one-indexed-inclusive should be less than end-line-one-indexed argument")
                  (t
                   (let ((selected (subseq lines (1- start-line-one-indexed-inclusive)
                                           (min end-line-one-indexed-inclusive num-lines))))
                     (with-output-to-string (s)
                       (format s "<file-content filename=~A from-line=~A to-line=~A>~%"
                               target-file
                               start-line-one-indexed-inclusive
                               end-line-one-indexed-inclusive)
                       (loop for line in selected
                             do (write-string line s)
                                (terpri s))
                       (format s "</file-content>")

                       (when (< end-line-one-indexed-inclusive num-lines)
                         (format s "~2%There is ~A more lines in the file."
                                 (- num-lines
                                    end-line-one-indexed-inclusive)))))))))
         (values result))
       
       
       )
      (t
       (fmt "File ~A NOT FOUND"
            target-file)))))


(defun-tool read-file ((target-file string "The path of the file to read. You can use either a relative path in the workspace or an absolute path. If an absolute path is provided, it will be preserved as is.")
                       (start-line-one-indexed-inclusive number "The one-indexed line number to start reading from (inclusive).")
                       (end-line-one-indexed-inclusive number "The one-indexed line number to end reading at (inclusive).")
                       (should-read-entire-file boolean "Whether to read the entire file. Defaults to false.")
                       (explanation string "One sentence explanation as to why this tool is being used, and how it contributes to the goal."))

  "
Read the contents of a file. the output of this tool call will be the 1-indexed file contents from start-line-one-indexed-inclusive to end-line-one-indexed-inclusive, together with a summary of the lines outside start-line-one-indexed-inclusive and end-line-one-indexed-inclusive.
Note that this call can view at most 250 lines at a time.

When using this tool to gather information, it's your responsibility to ensure you have the COMPLETE context. Specifically, each time you call this command you should:
1) Assess if the contents you viewed are sufficient to proceed with your task.
2) Take note of where there are lines not shown.
3) If the file contents you have viewed are insufficient, and you suspect they may be in lines not shown, proactively call the tool again to view those lines.
4) When in doubt, call this tool again to gather more information. Remember that partial file views may miss critical dependencies, imports, or functionality.

In some cases, if reading a range of lines is not enough, you may choose to read the entire file.
Reading entire files is often wasteful and slow, especially for large files (i.e. more than a few hundred lines). So you should use this option sparingly.
Reading the entire file is not allowed in most cases. You are only allowed to read the entire file if it has been edited or manually attached to the conversation by the user.
"
  (let ((response (%read-file target-file
                              start-line-one-indexed-inclusive
                              end-line-one-indexed-inclusive 
                              should-read-entire-file 
                              explanation)))
    (values response)))
