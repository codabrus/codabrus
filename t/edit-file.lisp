(uiop:define-package #:codabrus-tests/edit-file
  (:use #:cl)
  (:import-from #:rove
                #:deftest
                #:ok
                #:signals
                #:testing)
  (:import-from #:codabrus/tools/edit-file
                #:%replace-in-content
                #:%normalize-line-endings
                #:%detect-line-ending
                #:%to-crlf)
  (:import-from #:alexandria
                #:define-constant))
(in-package #:codabrus-tests/edit-file)


;;; Helpers

(define-constant +lf+ (string #\Newline)
  :test #'string=)

(define-constant +crlf+ (coerce '(#\Return #\Newline) 'string)
  :test #'string=)

(defun lf (&rest parts)
  "Join PARTS with actual LF newlines."
  (format nil "~{~A~^~%~}" parts))

(defun with-crlf (&rest parts)
  "Join PARTS with CRLF (\\r\\n) line endings."
  (cl-ppcre:regex-replace-all "\\n"
                               (apply #'lf parts)
                               +crlf+))


;;; Tests for %replace-in-content

(deftest test-simple-replace ()
  (testing "exact match replaces text"
    (ok (string= "hello world"
                 (%replace-in-content "hello foo" "foo" "world" nil))))
  (testing "replaces in the middle of a line"
    (ok (string= "aXc"
                 (%replace-in-content "abc" "b" "X" nil))))
  (testing "multiline exact match"
    (ok (string= (lf "line1" "new" "line3")
                 (%replace-in-content (lf "line1" "old" "line3") "old" "new" nil)))))

(deftest test-replace-all ()
  (testing "replaces every occurrence when replace-all is true"
    (ok (string= "X bar X baz X"
                 (%replace-in-content "foo bar foo baz foo" "foo" "X" t))))
  (testing "single occurrence with replace-all still works"
    (ok (string= "X"
                 (%replace-in-content "foo" "foo" "X" t))))
  (testing "replace-all with multiline blocks"
    (let* ((block (lf "alpha" "beta"))
           (content (lf block block "")))
      (ok (string= (lf "alpha" "gamma" "alpha" "gamma" "")
                   (%replace-in-content content (lf "alpha" "beta") (lf "alpha" "gamma") t))))))

(deftest test-multiple-match-error ()
  (testing "errors when old-string appears multiple times without replace-all"
    (signals (%replace-in-content "foo foo" "foo" "bar" nil))))

(deftest test-not-found-error ()
  (testing "errors when old-string is not in the file"
    (signals (%replace-in-content "hello world" "missing" "x" nil))))

(deftest test-identical-strings-error ()
  (testing "errors when old-string equals new-string"
    (signals (%replace-in-content "content" "content" "content" nil))))

(deftest test-empty-old-string-error ()
  (testing "empty old-string signals error"
    (signals (%replace-in-content "anything" "" "new" nil))))

(deftest test-line-trimmed-matching ()
  (testing "matches when lines have extra trailing whitespace"
    ;; Content has trailing spaces on each line; old-string doesn't
    (let ((content (lf "    def foo():   " "        pass   "))
          (old-str (lf "    def foo():" "        pass"))
          (new-str (lf "    def foo():" "        return 1")))
      (ok (string= (lf "    def foo():" "        return 1")
                   (%replace-in-content content old-str new-str nil)))))
  (testing "old-string with trimmed indentation still finds match"
    ;; Content has 4-space indent; old-string has no indent (trimmed)
    (let ((content (lf "" "    def foo():" "        pass" ""))
          (old-str (lf "def foo():" "    pass"))
          (new-str (lf "def foo():" "    return 1")))
      ;; The match is found; new-string replaces the ORIGINAL text literally
      (ok (string-search (lf "def foo():" "    return 1")
                         (%replace-in-content content old-str new-str nil))))))

(defun string-search (needle haystack)
  "Return non-NIL if NEEDLE is a substring of HAYSTACK."
  (search needle haystack :test #'char=))

(deftest test-indentation-flexible ()
  (testing "matches block with different common indentation"
    ;; Content has 4+8 spaces; old-string has 0+4 spaces
    (let ((content (lf "    if x:" "        foo()" "        bar()"))
          (old-str (lf "if x:" "    foo()" "    bar()"))
          (new-str (lf "if x:" "    baz()" "    bar()")))
      ;; The match is found; replacement is literal new-str
      (ok (string-search (lf "baz()" "    bar()")
                         (%replace-in-content content old-str new-str nil))))))

(deftest test-crlf-utilities ()
  (testing "%detect-line-ending returns :crlf for CRLF content"
    (ok (eq :crlf (%detect-line-ending (with-crlf "a" "b")))))
  (testing "%detect-line-ending returns :lf for LF content"
    (ok (eq :lf (%detect-line-ending (lf "a" "b")))))
  (testing "%normalize-line-endings converts CRLF to LF"
    (ok (string= (lf "a" "b")
                 (%normalize-line-endings (with-crlf "a" "b")))))
  (testing "%to-crlf converts LF to CRLF"
    (ok (string= (with-crlf "a" "b")
                 (%to-crlf (lf "a" "b")))))
  (testing "replace works on normalized content"
    (let* ((content (with-crlf "line1" "old" "line3" ""))
           (result  (%replace-in-content
                     (%normalize-line-endings content)
                     "old" "new" nil)))
      (ok (string= (lf "line1" "new" "line3" "") result)))))
