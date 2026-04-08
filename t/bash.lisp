(uiop:define-package #:codabrus-tests/bash
  (:use #:cl)
  (:import-from #:rove
                #:deftest
                #:ok
                #:testing)
  (:import-from #:codabrus/tools/bash
                #:%bash)
  (:import-from #:codabrus/vars
                #:*project-dir*))
(in-package #:codabrus-tests/bash)


;;; Helper — binds *project-dir* to a real directory so the tool is happy.
(defmacro with-tmpdir (&body body)
  `(let ((*project-dir* (uiop:temporary-directory)))
     ,@body))


(deftest test-captures-stdout
  (with-tmpdir
    (testing "stdout is returned"
      (ok (string= "hello" (str:trim (%bash "echo hello")))))))


(deftest test-captures-stderr
  (with-tmpdir
    (testing "stderr is merged with stdout"
      (ok (search "err-line" (%bash "echo err-line >&2"))))))


(deftest test-nonzero-exit-code
  (with-tmpdir
    (testing "non-zero exit code is included in output"
      (ok (search "Exit 1" (%bash "exit 1"))))
    (testing "non-zero exit code with message"
      (ok (search "Exit 2" (%bash "echo boom; exit 2"))))))


(deftest test-empty-output
  (with-tmpdir
    (testing "zero exit with no output returns placeholder"
      (ok (string= "(no output)" (%bash "true"))))))


(deftest test-output-truncation
  (with-tmpdir
    (testing "output over 4000 chars is truncated"
      ;; Generate 5000 'x' characters via printf
      (let ((result (%bash "printf '%5000s' '' | tr ' ' 'x'")))
        (ok (search "truncated" result))
        ;; Must not exceed limit + a small margin for the truncation message
        (ok (< (length result) 4200))))))


(deftest test-timeout
  (with-tmpdir
    (testing "long-running command is killed after timeout"
      (let ((result (%bash "sleep 60" :timeout 1)))
        (ok (search "timed out" result))))))
