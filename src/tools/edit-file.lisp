(uiop:define-package #:codabrus/tools/edit-file
  (:use #:cl)
  (:import-from #:40ants-ai-agents/tool
                #:defun-tool)
  (:import-from #:codabrus/vars
                #:*project-dir*)
  (:import-from #:serapeum
                #:fmt)
  (:import-from #:log
                #:info)
  (:export #:edit-file
           #:%replace-in-content
           #:%normalize-line-endings
           #:%detect-line-ending
           #:%to-crlf))
(in-package #:codabrus/tools/edit-file)


;;; Line-ending helpers

(defun %normalize-line-endings (text)
  "Convert all CRLF to LF."
  (cl-ppcre:regex-replace-all "\\r\\n" text (string #\Newline)))

(defun %detect-line-ending (text)
  "Return :CRLF or :LF based on what TEXT uses."
  (if (search (coerce '(#\Return #\Newline) 'string) text)
      :crlf
      :lf))

(defun %to-crlf (text)
  "Convert LF line endings to CRLF (assumes no existing CR before LF)."
  (cl-ppcre:regex-replace-all "\\n" text (coerce '(#\Return #\Newline) 'string)))


;;; Text utilities

(defun %split-lines (text)
  "Split TEXT into a list of lines (on #\Newline only)."
  (cl-ppcre:split "\\n" text :limit most-positive-fixnum))

(defun %line-start-offset (lines line-idx)
  "Return the character offset in the joined text where LINE-IDX (0-based) starts."
  (loop for k below line-idx sum (1+ (length (nth k lines)))))

(defun %lines-substring (content lines from-line to-line)
  "Extract the substring of CONTENT spanning FROM-LINE..TO-LINE (inclusive, 0-based)."
  (let* ((start (%line-start-offset lines from-line))
         (end (+ (%line-start-offset lines to-line)
                 (length (nth to-line lines)))))
    (subseq content start (min end (length content)))))


;;; Levenshtein distance

(defun %levenshtein (a b)
  "Return the Levenshtein distance between strings A and B."
  (let ((la (length a)) (lb (length b)))
    (cond
      ((zerop la) lb)
      ((zerop lb) la)
      (t
       (let ((m (make-array (list (1+ la) (1+ lb))
                            :element-type 'fixnum
                            :initial-element 0)))
         (dotimes (i (1+ la)) (setf (aref m i 0) i))
         (dotimes (j (1+ lb)) (setf (aref m 0 j) j))
         (loop for i from 1 to la do
           (loop for j from 1 to lb do
             (setf (aref m i j)
                   (if (char= (char a (1- i)) (char b (1- j)))
                       (aref m (1- i) (1- j))
                       (1+ (min (aref m (1- i) j)
                                (aref m i (1- j))
                                (aref m (1- i) (1- j))))))))
         (aref m la lb))))))


;;; Replacers
;;;
;;; Each replacer is a function (content find) -> list-of-strings.
;;; Each returned string is a substring of CONTENT that "matches" FIND.
;;; The replace loop uses content.indexOf(match) to locate and replace it.

(defun %simple-replacer (content find)
  "Return FIND if it appears exactly in CONTENT."
  (when (search find content :test #'char=)
    (list find)))

(defun %line-trimmed-replacer (content find)
  "Match lines by comparing trimmed versions; return the original (un-trimmed) slices."
  (let* ((orig-lines (%split-lines content))
         (search-lines (%split-lines find))
         (n-orig (length orig-lines))
         results)
    (when (and search-lines (string= "" (car (last search-lines))))
      (setf search-lines (butlast search-lines)))
    (let ((n-search (length search-lines)))
      (when (zerop n-search) (return-from %line-trimmed-replacer nil))
      (loop for i from 0 to (- n-orig n-search) do
        (when (loop for j below n-search
                    always (string= (string-trim '(#\Space #\Tab)
                                                  (nth (+ i j) orig-lines))
                                    (string-trim '(#\Space #\Tab)
                                                  (nth j search-lines))))
          (push (%lines-substring content orig-lines i (+ i n-search -1))
                results))))
    (nreverse results)))

(defun %whitespace-normalized-replacer (content find)
  "Match blocks where all whitespace runs are collapsed to a single space."
  (labels ((normalize (text)
             (string-trim '(#\Space #\Tab #\Newline)
                           (cl-ppcre:regex-replace-all "\\s+" text " "))))
    (let* ((norm-find (normalize find))
           (content-lines (%split-lines content))
           (find-lines (%split-lines find))
           (n-find (length find-lines))
           (n-content (length content-lines))
           results)
      (loop for i from 0 to (- n-content n-find) do
        (let ((block (%lines-substring content content-lines i (+ i n-find -1))))
          (when (string= (normalize block) norm-find)
            (push block results))))
      (nreverse results))))

(defun %indentation-flexible-replacer (content find)
  "Match blocks ignoring common leading indentation."
  (labels ((min-indent (lines)
             (loop for l in lines
                   unless (zerop (length (string-trim '(#\Space #\Tab) l)))
                   minimize (- (length l)
                               (length (string-left-trim '(#\Space #\Tab) l)))
                   into m
                   finally (return (or m 0))))
           (strip-indent (text)
             (let* ((lines (%split-lines text))
                    (non-empty (remove-if
                                (lambda (l)
                                  (zerop (length (string-trim '(#\Space #\Tab) l))))
                                lines))
                    (ind (if non-empty (min-indent non-empty) 0)))
               (with-output-to-string (s)
                 (loop for (l . rest) on lines do
                   (write-string
                    (if (zerop (length (string-trim '(#\Space #\Tab) l)))
                        l
                        (subseq l (min ind (length l))))
                    s)
                   (when rest (write-char #\Newline s)))))))
    (let* ((norm-find (strip-indent find))
           (content-lines (%split-lines content))
           (find-lines (%split-lines find))
           (n-find (length find-lines))
           (n-content (length content-lines))
           results)
      (loop for i from 0 to (- n-content n-find) do
        (let ((block (%lines-substring content content-lines i (+ i n-find -1))))
          (when (string= (strip-indent block) norm-find)
            (push block results))))
      (nreverse results))))

(defconstant +single-sim-threshold+ 0.0)
(defconstant +multi-sim-threshold+ 0.3)

(defun %block-anchor-replacer (content find)
  "Fuzzy match using first/last lines as anchors, Levenshtein similarity for middle lines."
  (let* ((search-lines (%split-lines find))
         (content-lines (%split-lines content))
         (n-content (length content-lines)))
    (when (and search-lines (string= "" (car (last search-lines))))
      (setf search-lines (butlast search-lines)))
    (let ((n-search (length search-lines)))
      (when (< n-search 3) (return-from %block-anchor-replacer nil))
      (let* ((first-trimmed (string-trim '(#\Space #\Tab) (first search-lines)))
             (last-trimmed  (string-trim '(#\Space #\Tab) (car (last search-lines))))
             candidates)
        ;; Collect (start . end) pairs where first and last lines match
        (loop for i from 0 below n-content do
          (when (string= (string-trim '(#\Space #\Tab) (nth i content-lines))
                         first-trimmed)
            (loop for j from (+ i 2) below n-content do
              (when (string= (string-trim '(#\Space #\Tab) (nth j content-lines))
                             last-trimmed)
                (push (cons i j) candidates)
                (return)))))
        (when (null candidates)
          (return-from %block-anchor-replacer nil))
        (labels ((similarity (start end)
                   (let* ((actual-size (1+ (- end start)))
                          (lines-to-check (min (- n-search 2)
                                               (- actual-size 2))))
                     (if (<= lines-to-check 0)
                         1.0
                         (/ (loop for j from 1 below (1- n-search)
                                  when (< j (1- actual-size))
                                  sum
                                  (let* ((orig (string-trim '(#\Space #\Tab)
                                                             (nth (+ start j) content-lines)))
                                         (srch (string-trim '(#\Space #\Tab)
                                                             (nth j search-lines)))
                                         (max-len (max (length orig) (length srch))))
                                    (if (zerop max-len)
                                        0.0
                                        (- 1.0 (/ (%levenshtein orig srch)
                                                   (float max-len))))))
                            (float lines-to-check))))))
          (if (= 1 (length candidates))
              (let* ((cand (first candidates))
                     (start (car cand)) (end (cdr cand)))
                (when (>= (similarity start end) +single-sim-threshold+)
                  (list (%lines-substring content content-lines start end))))
              (let ((best nil) (max-sim -1.0))
                (dolist (cand candidates)
                  (let ((sim (similarity (car cand) (cdr cand))))
                    (when (> sim max-sim)
                      (setf max-sim sim best cand))))
                (when (and best (>= max-sim +multi-sim-threshold+))
                  (list (%lines-substring content content-lines
                                          (car best) (cdr best)))))))))))

(defun %trimmed-boundary-replacer (content find)
  "Try matching the trimmed version of FIND."
  (let ((trimmed (string-trim '(#\Space #\Tab #\Newline) find)))
    (when (and (not (string= trimmed find))
               (search trimmed content :test #'char=))
      (list trimmed))))

(defun %multi-occurrence-replacer (content find)
  "Yield FIND for each occurrence (enables the multiple-match error path)."
  (when (search find content :test #'char=)
    (list find)))


;;; Main replace function

(defun %replace-in-content (content old-string new-string replace-all)
  "Replace OLD-STRING in CONTENT with NEW-STRING.
REPLACE-ALL replaces every occurrence; otherwise exactly one match is required."
  (when (string= old-string "")
    (error "Empty old-string is not allowed in %replace-in-content; use file creation path."))
  (when (string= old-string new-string)
    (error "No changes to apply: old-string and new-string are identical."))
  (let (found-any)
    (dolist (replacer (list #'%simple-replacer
                            #'%line-trimmed-replacer
                            #'%block-anchor-replacer
                            #'%whitespace-normalized-replacer
                            #'%indentation-flexible-replacer
                            #'%trimmed-boundary-replacer
                            #'%multi-occurrence-replacer))
      (dolist (search-str (funcall replacer content old-string))
        (let ((first-pos (search search-str content :test #'char=)))
          (when first-pos
            (setf found-any t)
            (when replace-all
              (return-from %replace-in-content
                (with-output-to-string (s)
                  (loop with from = 0
                        with slen = (length search-str)
                        for pos = (search search-str content :start2 from :test #'char=)
                        while pos
                        do (write-string content s :start from :end pos)
                           (write-string new-string s)
                           (setf from (+ pos slen))
                        finally (write-string content s :start from)))))
            (let ((last-pos (search search-str content :from-end t :test #'char=)))
              (when (= first-pos last-pos)
                (return-from %replace-in-content
                  (concatenate 'string
                               (subseq content 0 first-pos)
                               new-string
                               (subseq content (+ first-pos (length search-str)))))))))))
    (if found-any
        (error "Found multiple matches for old-string. Provide more surrounding context to make it unique, or use REPLACE-ALL.")
        (error "Could not find old-string in the file. It must match exactly, including whitespace and indentation."))))


;;; Public tool

(defun %edit-file (target-file instructions old-string new-string replace-all)
  (info "Editing file" target-file instructions)
  (let ((pathname (if (uiop:absolute-pathname-p (pathname target-file))
                      (pathname target-file)
                      (merge-pathnames target-file *project-dir*))))
    (cond
      ((string= old-string "")
       (ensure-directories-exist pathname)
       (alexandria:write-string-into-file new-string pathname
                                          :if-exists :supersede
                                          :if-does-not-exist :create)
       "File created successfully.")
      (t
       (unless (probe-file pathname)
         (error "File ~A not found." target-file))
       (let* ((content  (alexandria:read-file-into-string pathname
                                                          :external-format :utf-8))
              (ending   (%detect-line-ending content))
              (norm-c   (%normalize-line-endings content))
              (norm-old (%normalize-line-endings old-string))
              (norm-new (%normalize-line-endings new-string))
              (result   (%replace-in-content norm-c norm-old norm-new replace-all))
              (final    (if (eq ending :crlf) (%to-crlf result) result)))
         (alexandria:write-string-into-file final pathname :if-exists :supersede)
         "Edit applied successfully.")))))


(defun-tool edit-file ((target-file string "The path of the file to edit. Can be relative to the workspace or absolute.")
                       (instructions string "A single sentence describing what to change.")
                       (old-string string "The exact text to find and replace. Pass an empty string to create a new file.")
                       (new-string string "The replacement text. Must differ from old-string.")
                       (replace-all boolean "Set to true to replace every occurrence. Default: false."))
  "Performs exact string replacements in files.

Usage:
- Read the file first before editing so you know the exact content.
- OLD-STRING must match exactly, including whitespace and indentation.
- The edit will FAIL if OLD-STRING is not found in the file.
- The edit will FAIL if OLD-STRING matches in multiple places; in that case either
  add more surrounding context to OLD-STRING or set REPLACE-ALL to true.
- To create a new file, pass an empty OLD-STRING.
"
  (handler-case
      (%edit-file target-file instructions old-string new-string replace-all)
    (error (e)
      (fmt "Error: ~A" e))))
