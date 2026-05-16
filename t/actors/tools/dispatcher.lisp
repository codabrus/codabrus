(uiop:define-package #:codabrus-tests/actors/tools/dispatcher
  (:use #:cl)
  (:import-from #:rove
                #:deftest
                #:ok
                #:testing)
  (:import-from #:codabrus/actors/actor-system
                #:ensure-actor-system
                #:stop-actor-system)
  (:import-from #:codabrus/actors/tools/dispatcher
                #:make-tools-dispatcher)
  (:import-from #:codabrus/actors/tools/bash
                #:make-bash
                #:bash-stdout))
(in-package #:codabrus-tests/actors/tools/dispatcher)


(deftest test-dispatcher-runs-two-bash-tools
  (ensure-actor-system)
  (unwind-protect
       (let ((callback-called nil)
             (callback-lock (bt2:make-lock))
             (callback-cvar (bt2:make-condition-variable))
             (callback-result nil))
         (let ((dispatcher (make-tools-dispatcher)))
           (act:ask dispatcher
                    (list :run
                          :tool-specs (list (list 'make-bash "echo hello")
                                            (list 'make-bash "echo world"))
                          :on-completion (lambda (message &key actor tools &allow-other-keys)
                                           (declare (ignore actor))
                                           (bt2:with-lock-held (callback-lock)
                                             (setf callback-called t
                                                   callback-result (list message tools))
                                             (bt2:condition-broadcast callback-cvar)))))
           ;; Waiting when callback will be called
           (bt2:with-lock-held (callback-lock)
             (unless callback-called
               (bt2:condition-wait callback-cvar callback-lock :timeout 10)))
           
           (testing "callback was called"
             (ok callback-called))
           (testing "message type is :completed"
             (ok (eq (first callback-result) :completed)))
           (testing "two tools completed"
             (ok (= (length (second callback-result)) 2)))
           (let ((outputs (sort
                           (loop for tool in (second callback-result)
                                 collect (str:join #\Newline
                                                   (coerce
                                                    (bash-stdout
                                                     (act:ask-s tool :get-state))
                                                    'list)))
                           #'string<)))
             (testing "first tool output"
               (ok (search "hello" (first outputs))))
             (testing "second tool output"
               (ok (search "world" (second outputs)))))))
    (stop-actor-system)
    (values)))
