(uiop:define-package #:codabrus-tests/message
  (:use #:cl)
  (:import-from #:rove
                #:deftest
                #:ok
                #:testing)
  (:import-from #:codabrus/message
                #:message
                #:message-role
                #:message-parts
                #:message-text
                #:text-part
                #:text-part-content
                #:tool-call-part
                #:tool-call-part-tool-name
                #:tool-call-part-call-id
                #:tool-call-part-raw-args
                #:tool-result-part
                #:tool-result-part-call-id
                #:tool-result-part-output
                #:step-end-part
                #:step-end-part-finish-reason
                #:step-end-part-tokens-in
                #:step-end-part-tokens-out
                #:step-end-part-cost-usd
                #:make-text-part
                #:make-tool-call-part
                #:make-tool-result-part
                #:make-step-end-part
                #:make-user-message
                #:make-assistant-message)
  (:import-from #:40ants-ai-agents/ai-agent
                #:to-api-messages))
(in-package #:codabrus-tests/message)


(deftest test-part-construction ()
  (testing "text-part"
    (let ((p (make-text-part "hello")))
      (ok (typep p 'text-part))
      (ok (string= "hello" (text-part-content p)))))
  (testing "tool-call-part"
    (let ((p (make-tool-call-part "read-file" "call_123" "{\"target_file\":\"foo.lisp\"}")))
      (ok (typep p 'tool-call-part))
      (ok (string= "read-file" (tool-call-part-tool-name p)))
      (ok (string= "call_123" (tool-call-part-call-id p)))
      (ok (string= "{\"target_file\":\"foo.lisp\"}" (tool-call-part-raw-args p)))))
  (testing "tool-result-part"
    (let ((p (make-tool-result-part "call_123" "file contents")))
      (ok (typep p 'tool-result-part))
      (ok (string= "call_123" (tool-result-part-call-id p)))
      (ok (string= "file contents" (tool-result-part-output p)))))
  (testing "step-end-part"
    (let ((p (make-step-end-part :stop 100 50 0.003)))
      (ok (typep p 'step-end-part))
      (ok (eq :stop (step-end-part-finish-reason p)))
      (ok (= 100 (step-end-part-tokens-in p)))
      (ok (= 50 (step-end-part-tokens-out p)))
      (ok (< (abs (- 0.003 (step-end-part-cost-usd p))) 0.0001)))))


(deftest test-message-construction ()
  (testing "user message"
    (let ((msg (make-user-message "fix the tests")))
      (ok (typep msg 'message))
      (ok (eq :user (message-role msg)))
      (ok (= 1 (length (message-parts msg))))
      (ok (string= "fix the tests" (message-text msg)))))
  (testing "assistant message with parts"
    (let ((msg (make-assistant-message
                (list (make-tool-call-part "search" "call_1" "{\"term\":\"foo\"}")
                      (make-tool-result-part "call_1" "found 3 matches")
                      (make-text-part "I found 3 matches for foo.")))))
      (ok (eq :assistant (message-role msg)))
      (ok (= 3 (length (message-parts msg))))
      (ok (string= "I found 3 matches for foo." (message-text msg))))))


(deftest test-to-api-messages-user ()
  (let* ((msg (make-user-message "hello"))
         (api (to-api-messages msg)))
    (ok (= 1 (length api)))
    (let ((entry (first api)))
      (ok (string= "user" (cdr (assoc :role entry))))
      (ok (string= "hello" (cdr (assoc :content entry)))))))


(deftest test-to-api-messages-assistant-text-only ()
  (let* ((msg (make-assistant-message (list (make-text-part "response text"))))
         (api (to-api-messages msg)))
    (ok (= 1 (length api)))
    (let ((entry (first api)))
      (ok (string= "assistant" (cdr (assoc :role entry))))
      (ok (string= "response text" (cdr (assoc :content entry)))))))


(deftest test-to-api-messages-assistant-with-tools ()
  (let* ((msg (make-assistant-message
               (list (make-tool-call-part "read-file" "call_abc" "{\"target_file\":\"foo.lisp\"}")
                     (make-tool-result-part "call_abc" "file contents here")
                     (make-text-part "Here is the file."))))
         (api (to-api-messages msg)))
    (ok (= 3 (length api)))
    (let ((assistant-entry (first api)))
      (ok (string= "assistant" (cdr (assoc "role" assistant-entry :test #'string=))))
      (ok (null (cdr (assoc "content" assistant-entry :test #'string=))))
      (let ((tool-calls (cdr (assoc "tool_calls" assistant-entry :test #'string=))))
        (ok (= 1 (length tool-calls)))
        (let ((tc (first tool-calls)))
          (ok (string= "call_abc" (cdr (assoc :id tc))))
          (ok (string= "read-file"
                       (cdr (assoc :name (cdr (assoc :function tc)))))))))
    (let ((tool-result-entry (second api)))
      (ok (string= "tool" (cdr (assoc :role tool-result-entry))))
      (ok (string= "call_abc" (cdr (assoc :tool_call_id tool-result-entry))))
      (ok (string= "file contents here" (cdr (assoc :content tool-result-entry)))))
    (let ((text-entry (third api)))
      (ok (string= "assistant" (cdr (assoc :role text-entry))))
      (ok (string= "Here is the file." (cdr (assoc :content text-entry)))))))
