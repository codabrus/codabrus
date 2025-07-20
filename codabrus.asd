#-asdf3.1 (error "codabrus requires ASDF 3.1 because for lower versions pathname does not work for package-inferred systems.")
(defsystem "codabrus"
  :description "Hackable AI Code Assistant written in Common Lisp."
  :author "Alexander Artemenko <svetlyak.40wt@gmail.com>"
  :license "Unlicense"
  :homepage "https://codabrus.org"
  :source-control (:git "https://github.org/codabrus/codabrus")
  :bug-tracker "https://github.org/codabrus/codabrus/issues"
  :class :40ants-asdf-system
  :defsystem-depends-on ("40ants-asdf-system")
  :pathname "src"
  :depends-on ("codabrus/core")
  :in-order-to ((test-op (test-op "codabrus-tests"))))


(asdf:register-system-packages "log4cl" '("LOG"))
