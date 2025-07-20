(defsystem "codabrus-docs"
  :author "Alexander Artemenko <svetlyak.40wt@gmail.com>"
  :license "Unlicense"
  :homepage "https://codabrus.org"
  :class :package-inferred-system
  :description "Provides documentation for codabrus."
  :source-control (:git "https://github.org/codabrus/codabrus")
  :bug-tracker "https://github.org/codabrus/codabrus/issues"
  :pathname "docs"
  :depends-on ("codabrus"
               "codabrus-docs/index"))
