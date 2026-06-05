(uiop:define-package #:codabrus-tests/actors/tools/bash
  (:use #:cl)
  (:import-from #:rove
                #:deftest
                #:ok
                #:testing)
  (:import-from #:codabrus/actors/actor-system
                #:ensure-actor-system
                #:stop-actor-system)
  (:import-from #:codabrus/actors/tools/bash
                #:make-bash))
(in-package #:codabrus-tests/actors/tools/bash)


(deftest test-bash-interrupt
  (ensure-actor-system)
  (unwind-protect
       (let ((callback-called nil)
             (callback-result nil)
             (lock (bt2:make-lock))
             (cvar (bt2:make-condition-variable)))
         (let ((tool (make-bash "sleep 30")))
           (act:ask tool
                    (list :run
                          :on-completion (lambda (message &key actor &allow-other-keys)
                                           (declare (ignore actor))
                                           (bt2:with-lock-held (lock)
                                             (setf callback-called t
                                                   callback-result message)
                                             (bt2:condition-broadcast cvar)))))
           (sleep 1)
           (act:ask tool (list :interrupt))
           (bt2:with-lock-held (lock)
             (unless callback-called
               (bt2:condition-wait cvar lock :timeout 5)))
           (testing "callback was called with :interrupted"
             (ok callback-called)
             (ok (eq callback-result :interrupted)))))
    (stop-actor-system)
    (values)))


(deftest test-render-tool-result
  (ensure-actor-system)
  (unwind-protect
       (let ((callback-result nil)
             (lock (bt2:make-lock))
             (cvar (bt2:make-condition-variable)))
         (let ((tool (make-bash "echo hello")))
           (act:ask tool
                    (list :run
                          :on-completion (lambda (message &key result &allow-other-keys)
                                           (declare (ignore message))
                                           (bt2:with-lock-held (lock)
                                             (setf callback-result result)
                                             (bt2:condition-broadcast cvar)))))
           (bt2:with-lock-held (lock)
             (unless callback-result
               (bt2:condition-wait cvar lock :timeout 10)))
            (testing "render-tool-result returns stdout"
              (ok (search "hello" callback-result)))))
    (stop-actor-system)
    (values)))
