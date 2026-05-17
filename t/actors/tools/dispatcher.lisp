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


(deftest test-dispatcher-sequential-runs
  "This test checks if dispatcher will serialize consequent calls to :run."
  (let ((tmpfile (merge-pathnames "codabrus-dispatcher-test-foo" (uiop:temporary-directory))))
    (uiop:delete-file-if-exists tmpfile)
    (ensure-actor-system)
    (unwind-protect
         (let ((rounds-completed 0)
               (all-tools nil)
               (lock (bt2:make-lock))
               (cvar (bt2:make-condition-variable)))
           (let ((dispatcher (make-tools-dispatcher)))
             (act:ask dispatcher
                      (list :run
                            :tool-specs (list (list 'make-bash
                                                    (format nil "sleep 1 && echo Some > ~A"
                                                            (namestring tmpfile))))
                            :on-completion (lambda (message &key tools &allow-other-keys)
                                             (declare (ignore message))
                                             (bt2:with-lock-held (lock)
                                               (incf rounds-completed)
                                               (setf all-tools (append all-tools tools))
                                               (bt2:condition-broadcast cvar)))))
             (act:ask dispatcher
                      (list :run
                            :tool-specs (list (list 'make-bash
                                                    (format nil "cat ~A"
                                                            (namestring tmpfile))))
                            :on-completion (lambda (message &key tools &allow-other-keys)
                                             (declare (ignore message))
                                             (bt2:with-lock-held (lock)
                                               (incf rounds-completed)
                                               (setf all-tools (append all-tools tools))
                                               (bt2:condition-broadcast cvar)))))
             
             ;; Wait while both :runs will complete
             (bt2:with-lock-held (lock)
               (loop while (< rounds-completed 2)
                     do (bt2:condition-wait cvar lock :timeout 15)))
             
             (testing "both rounds completed"
               (ok (= rounds-completed 2)))
             
             (let ((cat-output (str:join #\Newline
                                         (coerce
                                          (bash-stdout
                                           (act:ask-s (second all-tools) :get-state))
                                          'list))))
               (testing "cat read the file written by first run"
                 (ok (search "Some" cat-output))))))
       (uiop:delete-file-if-exists tmpfile)
       (stop-actor-system)
       (values))))


(deftest test-dispatcher-interrupt
  (ensure-actor-system)
  (unwind-protect
       (let ((callback-called nil)
             (callback-result nil)
             (lock (bt2:make-lock))
             (cvar (bt2:make-condition-variable)))
         (let ((dispatcher (make-tools-dispatcher)))
           (act:ask dispatcher
                    (list :run
                          :tool-specs (list (list 'make-bash "sleep 30")
                                            (list 'make-bash "sleep 30"))
                          :on-completion (lambda (message &key actor &allow-other-keys)
                                           (declare (ignore actor))
                                           (bt2:with-lock-held (lock)
                                             (setf callback-called t
                                                   callback-result message)
                                             (bt2:condition-broadcast cvar)))))
           (sleep 1)
           (act:ask dispatcher (list :interrupt))
           (bt2:with-lock-held (lock)
             (unless callback-called
               (bt2:condition-wait cvar lock :timeout 5)))
           (testing "callback was called with :interrupted"
             (ok callback-called)
             (ok (eq callback-result :interrupted)))))
    (stop-actor-system)
    (values)))
