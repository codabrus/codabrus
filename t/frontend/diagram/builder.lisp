(uiop:define-package #:codabrus-tests/frontend/diagram/builder
  (:use #:cl)
  (:import-from #:rove
                #:deftest
                #:ok
                #:testing))
(in-package #:codabrus-tests/frontend/diagram/builder)


(defun make-msg (role content &key tool-calls tool-call-id)
  (let ((ht (serapeum:dict "role" role "content" content)))
    (when tool-calls
      (setf (gethash "tool_calls" ht) (coerce tool-calls 'vector)))
    (when tool-call-id
      (setf (gethash "tool_call_id" ht) tool-call-id))
    ht))


(defun make-tool-call (id fn-name arguments)
  (serapeum:dict "id" id
                 "function" (serapeum:dict "name" fn-name
                                           "arguments" arguments)))


(deftest test-truncate-string ()
  (testing "short string passes through"
    (ok (string= "hello" (codabrus/frontend/diagram/builder::truncate-string "hello" 10))))
  (testing "long string is truncated"
    (ok (string= "hello w..." (codabrus/frontend/diagram/builder::truncate-string "hello world" 7))))
  (testing "whitespace is trimmed"
    (ok (string= "hi" (codabrus/frontend/diagram/builder::truncate-string "  hi  " 10)))))


(deftest test-build-diagram-data-basic ()
  (testing "single system message"
    (let* ((msgs (list (make-msg "system" "You are helpful")))
           (data (codabrus/frontend/diagram/builder::build-diagram-data msgs))
           (nodes (gethash "nodes" data))
           (edges (gethash "edges" data)))
      (ok (= 1 (length nodes)))
      (ok (null edges))
      (let ((n (first nodes)))
        (ok (string= "m0" (gethash "id" n)))
        (ok (string= "You are helpful" (gethash "label" n))))))

  (testing "system -> user chain"
    (let* ((msgs (list (make-msg "system" "prompt")
                       (make-msg "user" "hello")))
           (data (codabrus/frontend/diagram/builder::build-diagram-data msgs))
           (nodes (gethash "nodes" data))
           (edges (gethash "edges" data)))
      (ok (= 2 (length nodes)))
      (ok (= 1 (length edges)))
      (ok (string= "m0" (gethash "source" (first edges))))
      (ok (string= "m1" (gethash "target" (first edges)))))))


(deftest test-build-diagram-with-tool-calls ()
  (testing "assistant with tool calls creates branch nodes"
    (let* ((msgs (list (make-msg "user" "list files")
                       (make-msg "assistant" "NULL"
                                 :tool-calls (list (make-tool-call "call_001" "BASH" "{}")))
                       (make-msg "tool" "file1.txt"
                                 :tool-call-id "call_001")))
           (data (codabrus/frontend/diagram/builder::build-diagram-data msgs))
           (nodes (gethash "nodes" data))
           (edges (gethash "edges" data)))
      (ok (= 3 (length nodes)))
      (ok (= 2 (length edges)))
      (let ((tool-node (find-if (lambda (n) (string= "tc_call_001" (gethash "id" n))) nodes)))
        (ok tool-node "tool branch node exists")
        (ok (string= "file1.txt" (gethash "label" tool-node))
            "tool node label updated with result"))))

  (testing "node data is stored for popup"
    (let* ((msgs (list (make-msg "user" "hello")))
           (data (codabrus/frontend/diagram/builder::build-diagram-data msgs))
           (node-data (codabrus/frontend/diagram/builder::get-node-data "m0")))
      (ok node-data)
      (ok (string= "user" (gethash "role" node-data)))
      (ok (string= "hello" (gethash "content" node-data))))))


(deftest test-diagram-to-json ()
  (testing "produces valid JSON"
    (let* ((msgs (list (make-msg "system" "test")
                       (make-msg "user" "hi")))
           (data (codabrus/frontend/diagram/builder::build-diagram-data msgs))
           (json (codabrus/frontend/diagram/builder::diagram-to-json data))
           (parsed (yason:parse json)))
      (ok (= 2 (length (gethash "nodes" parsed))))
      (ok (= 1 (length (gethash "edges" parsed)))))))
