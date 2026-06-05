(uiop:define-package #:codabrus/frontend/diagram/builder
  (:use #:cl)
  (:import-from #:serapeum
                #:dict
                #:~>)
  (:import-from #:yason)
  (:import-from #:codabrus/actors/llm-agent
                #:llm-agent-messages)
  (:export #:*node-data*
           #:build-diagram-data
           #:get-node-data
           #:diagram-to-json
           #:truncate-string))
(in-package #:codabrus/frontend/diagram/builder)


(defvar *node-data* (make-hash-table :test 'equal))


(defun truncate-string (str max-len)
  (let ((s (string-trim '(#\Newline #\Space #\Tab) str)))
    (if (<= (length s) max-len)
        s
        (concatenate 'string (subseq s 0 max-len) "..."))))


(defun node-attrs (role)
  (ecase role
    (:system
     (dict "body" (dict "fill" "#94a3b8" "stroke" "#64748b" "rx" 6 "ry" 6)
           "label" (dict "fill" "#fff" "fontSize" 11)))
    (:user
     (dict "body" (dict "fill" "#3b82f6" "stroke" "#2563eb" "rx" 6 "ry" 6)
           "label" (dict "fill" "#fff" "fontSize" 12)))
    (:assistant
     (dict "body" (dict "fill" "#22c55e" "stroke" "#16a34a" "rx" 6 "ry" 6)
           "label" (dict "fill" "#fff" "fontSize" 12)))
    (:tool
     (dict "body" (dict "fill" "#f59e0b" "stroke" "#d97706" "rx" 6 "ry" 6)
           "label" (dict "fill" "#fff" "fontSize" 11)))))


(defun make-node (id x y label role &optional (width 160) (height 36))
  (dict "id" id
        "x" x
        "y" y
        "width" width
        "height" height
        "label" label
        "attrs" (node-attrs role)))


(defun make-edge (source target &key (source-anchor "right") (target-anchor "left"))
  (dict "source" (dict "cell" source "anchor" source-anchor)
        "target" (dict "cell" target "anchor" target-anchor)
        "router" (dict "name" "manhattan")
        "connector" (dict "name" "rounded")))


(defun store-node-data (id role content &key tool-call-id tool-name tool-args)
  (let ((data (dict "role" (string-downcase (symbol-name role))
                    "content" (or content ""))))
    (when tool-call-id
      (setf (gethash "tool-call-id" data) tool-call-id))
    (when tool-name
      (setf (gethash "tool-name" data) tool-name))
    (when tool-args
      (setf (gethash "tool-args" data) tool-args))
    (setf (gethash id *node-data*) data)))


(defun get-node-data (node-id)
  (gethash node-id *node-data*))


(defun tool-call-name (tc)
  (gethash "name" (gethash "function" tc)))


(defun tool-call-args (tc)
  (gethash "arguments" (gethash "function" tc)))


(defun format-tool-calls-summary (tool-calls)
  (if (= (length tool-calls) 1)
      (format nil "Call: ~A" (tool-call-name (aref tool-calls 0)))
      (format nil "Call ~A tools" (length tool-calls))))


(defun format-tool-calls-detail (tool-calls)
  (with-output-to-string (s)
    (loop for tc across tool-calls
          for i from 1
          do (format s "~:[~;~%~%---~]Tool ~A: ~A~%Arguments: ~A"
                     (> i 1) i (tool-call-name tc) (tool-call-args tc)))))


(defun build-diagram-data (messages)
  (clrhash *node-data*)
  (let ((nodes nil)
        (edges nil)
        (main-chain-x 80)
        (prev-main-node-id nil)
        (tool-call-id->node-id (make-hash-table :test 'equal))
        (branch-y-offsets (make-hash-table :test 'equal)))
    (loop for msg in messages
          for i from 0
          for role = (gethash "role" msg)
          for content = (gethash "content" msg)
          do (cond
               ((string= role "system")
                (let ((node-id (format nil "m~A" i))
                      (label (truncate-string content 20)))
                  (push (make-node node-id main-chain-x 100 label :system 180 40) nodes)
                  (store-node-data node-id :system content)
                  (when prev-main-node-id
                    (push (make-edge prev-main-node-id node-id) edges))
                  (setf prev-main-node-id node-id
                        main-chain-x (+ main-chain-x 220))))

               ((string= role "user")
                (let ((node-id (format nil "m~A" i))
                      (label (truncate-string content 25)))
                  (push (make-node node-id main-chain-x 100 label :user 180 40) nodes)
                  (store-node-data node-id :user content)
                  (when prev-main-node-id
                    (push (make-edge prev-main-node-id node-id) edges))
                  (setf prev-main-node-id node-id
                        main-chain-x (+ main-chain-x 220))))

               ((string= role "assistant")
                 (let* ((node-id (format nil "m~A" i))
                        (tool-calls (gethash "tool_calls" msg))
                        (has-content (and content (string/= content "NULL")))
                        (label (cond
                                 (has-content (truncate-string content 25))
                                 (tool-calls (format-tool-calls-summary tool-calls))
                                 (t "...")))
                        (popup-content (cond
                                         (has-content content)
                                         (tool-calls (format-tool-calls-detail tool-calls))
                                         (t ""))))
                   (push (make-node node-id main-chain-x 100 label :assistant 180 40) nodes)
                   (store-node-data node-id :assistant popup-content)
                  (when prev-main-node-id
                    (push (make-edge prev-main-node-id node-id) edges))
                  (when tool-calls
                    (let ((offset 0))
                      (loop for tc across tool-calls
                            for tc-id = (gethash "id" tc)
                            for tc-name = (tool-call-name tc)
                            for tc-node-id = (format nil "tc_~A" tc-id)
                            for branch-y = (+ 250 (* offset 100))
                            do (push (make-node tc-node-id
                                                main-chain-x branch-y
                                                tc-name :tool 160 36)
                                     nodes)
                               (push (make-edge node-id tc-node-id
                                                :source-anchor "bottom"
                                                :target-anchor "top") edges)
                               (setf (gethash tc-id tool-call-id->node-id) tc-node-id)
                                (store-node-data tc-node-id :tool nil
                                                  :tool-call-id tc-id
                                                  :tool-name tc-name
                                                  :tool-args (tool-call-args tc))
                               (setf (gethash node-id branch-y-offsets) (1+ offset))
                               (incf offset))))
                  (setf prev-main-node-id node-id
                        main-chain-x (+ main-chain-x 220))))

               ((string= role "tool")
                 (let* ((tc-id (gethash "tool_call_id" msg))
                        (tc-node-id (gethash tc-id tool-call-id->node-id)))
                   (when tc-node-id
                     (let ((label (truncate-string content 25))
                           (existing (gethash tc-node-id *node-data*)))
                       (when existing
                         (setf (gethash "content" existing) (or content ""))
                         (setf (gethash "role" existing) "tool"))
                       (loop for node in nodes
                             when (string= (gethash "id" node) tc-node-id)
                             do (setf (gethash "label" node) label))))))))
    (dict "nodes" (nreverse nodes)
          "edges" (nreverse edges))))


(defun diagram-to-json (diagram-data)
  (with-output-to-string (s)
    (yason:encode diagram-data s)))
