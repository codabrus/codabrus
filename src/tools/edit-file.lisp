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


(defun-tool edit-file ((target-file string "The path of the file to read. You can use either a relative path in the workspace or an absolute path. If an absolute path is provided, it will be preserved as is.")
                       (instructions string "A single sentence instruction describing what you are going to do for the sketched edit. This is used to assist the less intelligent model in applying the edit. Please use the first person to describe what you are going to do. Dont repeat what you have said previously in normal messages. And use it to disambiguate uncertainty in the edit.")
                       (code-edit string "Specify ONLY the precise lines of code that you wish to edit. **NEVER specify or write out unchanged code**. Instead, represent all unchanged code using the comment of the language you're editing in - example: `// ... existing code ...`"))

  "
Use this tool to propose an edit to an existing file.

This will be read by a less intelligent model, which will quickly apply the edit. You should make it clear what the edit is, while also minimizing the unchanged code you write.
When writing the edit, you should specify each edit in sequence, with the special comment `// ... existing code ...` to represent unchanged code in between edited lines.

For example:

```
// ... existing code ...
FIRST_EDIT
// ... existing code ...
SECOND_EDIT
// ... existing code ...
THIRD_EDIT
// ... existing code ...
```

You should still bias towards repeating as few lines of the original file as possible to convey the change.
But, each edit should contain sufficient context of unchanged lines around the code you're editing to resolve ambiguity.
DO NOT omit spans of pre-existing code (or comments) without using the `// ... existing code ...` comment to indicate its absence. If you omit the existing code comment, the model may inadvertently delete these lines.
Make sure it is clear what the edit should be, and where it should be applied.

You should specify the following arguments before the others: [target_file]
"

  (let ((response (%read-file target-file
                              start-line-one-indexed-inclusive
                              end-line-one-indexed-inclusive 
                              should-read-entire-file 
                              explanation)))
    (values response)))
