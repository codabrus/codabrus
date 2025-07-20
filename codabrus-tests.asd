(defsystem "codabrus-tests"
  :author "Alexander Artemenko <svetlyak.40wt@gmail.com>"
  :license "Unlicense"
  :homepage "https://codabrus.org"
  :class :package-inferred-system
  :description "Provides tests for codabrus."
  :source-control (:git "https://github.org/codabrus/codabrus")
  :bug-tracker "https://github.org/codabrus/codabrus/issues"
  :pathname "t"
  :depends-on ("codabrus-tests/core")
  :perform (test-op (op c)
                    (unless (symbol-call :rove :run c)
                      (error "Tests failed"))))
