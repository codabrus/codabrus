(uiop:define-package #:codabrus-tests/integration
  (:use #:cl)
  (:import-from #:rove
                #:deftest
                #:ok
                #:testing)
  (:import-from #:codabrus/session
                #:make-session
                #:run-session
                #:session-state)
  (:import-from #:40ants-ai-agents/state
                #:state-messages)
  (:import-from #:40ants-ai-agents/ai-message
                #:ai-message
                #:ai-message-text))
(in-package #:codabrus-tests/integration)


;;; Full round-trip smoke test.
;;;
;;; Skipped automatically when DEEPSEEK_API_TOKEN is unset so that
;;; the suite stays free of network calls in plain CI runs.
;;; Set the env var to run this test:
;;;   DEEPSEEK_API_TOKEN=sk-... qlot exec sbcl --eval '(asdf:test-system "codabrus")'

(deftest test-run-session-smoke
  (when (uiop:getenv "DEEPSEEK_API_TOKEN")
    (let* ((tmpdir (merge-pathnames
                    (format nil "codabrus-smoke-~A/" (get-universal-time))
                    (uiop:temporary-directory)))
           (hello-path (merge-pathnames "hello.txt" tmpdir)))
      (ensure-directories-exist tmpdir)
      (with-open-file (f hello-path :direction :output :if-does-not-exist :create)
        (write-string "xyzzy-marker-42" f))
      (unwind-protect
           (let* ((session (make-session tmpdir))
                  (result  (run-session session "Read hello.txt and tell me its exact contents.")))
             (testing "session has state after run"
               (ok (session-state result)))
             (let* ((msgs    (state-messages (session-state result)))
                    (ai-msg  (find-if (lambda (m) (typep m 'ai-message)) msgs)))
               (testing "AI responded"
                 (ok ai-msg))
               (testing "response mentions the known file contents"
                 (ok (search "xyzzy-marker-42" (ai-message-text ai-msg))))))
        (uiop:delete-directory-tree tmpdir :validate t :if-does-not-exist :ignore)))))
