(uiop:define-package #:codabrus-tests/session-store
  (:use #:cl)
  (:import-from #:rove
                #:deftest
                #:ok
                #:testing
                #:ng)
  (:import-from #:codabrus/session
                #:make-session
                #:session-id
                #:session-project-dir
                #:session-model
                #:session-state
                #:session-tokens-in
                #:session-tokens-out
                #:session-total-cost-usd
                #:session-created-at
                #:session-updated-at)
  (:import-from #:codabrus/session-store
                #:*sessions-dir*
                #:save-session
                #:load-session
                #:list-sessions
                #:delete-session
                #:session-file-path)
  (:import-from #:40ants-ai-agents/state
                #:state
                #:state-messages)
  (:import-from #:codabrus/message
                #:message
                #:message-role
                #:message-text
                #:message-parts
                #:text-part
                #:tool-call-part
                #:tool-result-part
                #:make-user-message
                #:make-assistant-message
                #:make-text-part
                #:make-tool-call-part
                #:make-tool-result-part))
(in-package #:codabrus-tests/session-store)


(defvar *test-dir* nil)


(defmacro with-test-session-dir (&body body)
  `(let* ((*sessions-dir* (merge-pathnames
                           (format nil "codabrus-test-sessions-~A/"
                                   (get-universal-time))
                           (uiop:temporary-directory))))
     (unwind-protect (progn ,@body)
       (when (probe-file *sessions-dir*)
         (uiop:delete-directory-tree *sessions-dir* :validate t :if-does-not-exist :ignore)))))


(deftest test-empty-session-roundtrip ()
  (with-test-session-dir
    (let* ((dir (merge-pathnames "project/" (uiop:temporary-directory)))
           (session (make-session dir))
           (path (save-session session)))
      (testing "file is created"
        (ok (probe-file path)))
      (testing "file has .md extension"
        (ok (string= "md" (pathname-type path))))
      (let ((loaded (load-session (session-id session))))
        (testing "id preserved"
          (ok (string= (session-id session) (session-id loaded))))
        (testing "project-dir preserved"
          (ok (equalp (session-project-dir session) (session-project-dir loaded))))
        (testing "model preserved"
          (ok (string= (session-model session) (session-model loaded))))
        (testing "tokens-in is 0"
          (ok (= 0 (session-tokens-in loaded))))
        (testing "tokens-out is 0"
          (ok (= 0 (session-tokens-out loaded))))
        (testing "cost is 0.0"
          (ok (= 0.0d0 (session-total-cost-usd loaded))))
        (testing "created-at preserved"
          (ok (string= (session-created-at session) (session-created-at loaded))))
        (testing "state is nil"
          (ok (null (session-state loaded))))))))


(deftest test-session-with-messages-roundtrip ()
  (with-test-session-dir
    (let* ((dir (merge-pathnames "project/" (uiop:temporary-directory)))
           (s1 (make-session dir))
           (msgs (list (make-user-message "fix the failing tests")
                       (make-assistant-message (list (make-text-part "I will investigate.")))))
           (state (state msgs))
           (session (make-session dir
                                  :id (session-id s1)
                                  :state state
                                  :tokens-in 500
                                  :tokens-out 200
                                  :total-cost-usd 0.003d0
                                  :created-at (session-created-at s1))))
      (save-session session)
      (let* ((loaded (load-session (session-id session)))
             (loaded-msgs (state-messages (session-state loaded))))
        (testing "messages count preserved"
          (ok (= 2 (length loaded-msgs))))
        (testing "user message text preserved"
          (let ((user-msg (find-if (lambda (m) (and (typep m 'message)
                                                     (eq (message-role m) :user)))
                                   loaded-msgs)))
            (ok user-msg)
            (when user-msg
              (ok (search "fix the failing tests" (message-text user-msg))))))
        (testing "assistant message text preserved"
          (let ((ai-msg (find-if (lambda (m) (and (typep m 'message)
                                                   (eq (message-role m) :assistant)))
                                 loaded-msgs)))
            (ok ai-msg)
            (when ai-msg
              (ok (search "I will investigate." (message-text ai-msg))))))
        (testing "tokens-in preserved"
          (ok (= 500 (session-tokens-in loaded))))
        (testing "tokens-out preserved"
          (ok (= 200 (session-tokens-out loaded))))
        (testing "cost preserved"
          (ok (= 0.003d0 (session-total-cost-usd loaded))))))))


(deftest test-session-with-tool-parts-roundtrip ()
  (with-test-session-dir
    (let* ((dir (merge-pathnames "project/" (uiop:temporary-directory)))
           (s1 (make-session dir))
           (msgs (list (make-user-message "read the file")
                       (make-assistant-message
                        (list (make-tool-call-part "read-file" "call_abc" "{\"target_file\":\"foo.lisp\"}")
                              (make-tool-result-part "call_abc" "file contents here")
                              (make-text-part "Here is the file.")))))
           (state (state msgs))
           (session (make-session dir
                                  :id (session-id s1)
                                  :state state
                                  :created-at (session-created-at s1))))
      (save-session session)
      (let* ((loaded (load-session (session-id session)))
             (loaded-msgs (state-messages (session-state loaded)))
             (assistant-msg (find-if (lambda (m) (and (typep m 'message)
                                                       (eq (message-role m) :assistant)))
                                     loaded-msgs)))
        (testing "assistant message found"
          (ok assistant-msg))
        (when assistant-msg
          (testing "parts count preserved"
            (ok (= 3 (length (message-parts assistant-msg)))))
          (testing "tool-call part preserved"
            (let ((tc (find-if (lambda (p) (typep p 'tool-call-part)) (message-parts assistant-msg))))
              (ok tc)
              (when tc
                (ok (string= "read-file" (slot-value tc 'codabrus/message::tool-name)))
                (ok (string= "call_abc" (slot-value tc 'codabrus/message::call-id))))))
          (testing "tool-result part preserved"
            (let ((tr (find-if (lambda (p) (typep p 'tool-result-part)) (message-parts assistant-msg))))
              (ok tr)
              (when tr
                (ok (string= "call_abc" (slot-value tr 'codabrus/message::call-id)))
                (ok (search "file contents" (slot-value tr 'codabrus/message::output))))))
          (testing "text part preserved"
            (ok (search "Here is the file." (message-text assistant-msg)))))))))


(deftest test-session-file-is-markdown ()
  (with-test-session-dir
    (let* ((dir (merge-pathnames "project/" (uiop:temporary-directory)))
           (session (make-session dir
                                  :tokens-in 42
                                  :tokens-out 10
                                  :total-cost-usd 0.05d0))
           (path (save-session session))
           (content (uiop:read-file-string path)))
      (testing "has frontmatter delimiters"
        (ok (search "---" content)))
      (testing "contains id"
        (ok (search (session-id session) content)))
      (testing "contains tokens-in"
        (ok (search "tokens-in: 42" content))))))


(deftest test-list-sessions ()
  (with-test-session-dir
    (let* ((dir1 (merge-pathnames "project1/" (uiop:temporary-directory)))
           (dir2 (merge-pathnames "project2/" (uiop:temporary-directory)))
           (s1 (make-session dir1))
           (s2 (make-session dir2)))
      (save-session s1)
      (save-session s2)
      (let ((sessions (list-sessions)))
        (testing "lists both sessions"
          (ok (= 2 (length sessions))))
        (testing "each entry has :id"
          (ok (every (lambda (fm) (assoc :id fm)) sessions)))
        (testing "each entry has :project-dir"
          (ok (every (lambda (fm) (assoc :project-dir fm)) sessions)))))))


(deftest test-delete-session ()
  (with-test-session-dir
    (let* ((dir (merge-pathnames "project/" (uiop:temporary-directory)))
           (session (make-session dir))
           (path (save-session session)))
      (testing "file exists before delete"
        (ok (probe-file path)))
      (delete-session (session-id session))
      (testing "file is gone after delete"
        (ng (probe-file path))))))


(deftest test-multiline-message-roundtrip ()
  (with-test-session-dir
    (let* ((dir (merge-pathnames "project/" (uiop:temporary-directory)))
           (s1 (make-session dir))
           (multi-text (format nil "line one~%line two~%line three"))
           (msgs (list (make-user-message multi-text)
                       (make-assistant-message (list (make-text-part "done")))))
           (state (state msgs))
           (session (make-session dir
                                  :id (session-id s1)
                                  :state state
                                  :created-at (session-created-at s1))))
      (save-session session)
      (let* ((loaded (load-session (session-id session)))
             (loaded-msgs (state-messages (session-state loaded)))
             (user-msg (find-if (lambda (m) (and (typep m 'message)
                                                  (eq (message-role m) :user)))
                                loaded-msgs)))
        (testing "multiline text preserved"
          (ok user-msg)
          (when user-msg
            (ok (string= multi-text (message-text user-msg)))))))))
