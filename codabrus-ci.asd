(defsystem "codabrus-ci"
  :author "Alexander Artemenko <svetlyak.40wt@gmail.com>"
  :license "Unlicense"
  :homepage "https://codabrus.org"
  :class :package-inferred-system
  :description "Provides CI settings for codabrus."
  :source-control (:git "https://github.org/codabrus/codabrus")
  :bug-tracker "https://github.org/codabrus/codabrus/issues"
  :pathname "src"
  :depends-on ("40ants-ci"
               "codabrus-ci/ci"))
