(uiop:define-package #:codabrus/vars
  (:use #:cl)
  (:import-from #:serapeum
                #:defvar-unbound)
  (:export #:*project-dir*
           #:*model*
           #:*token-readers*))
(in-package #:codabrus/vars)


(defvar-unbound *project-dir*
  "An absolute path to the root directory of the current project.")

(defparameter *model* "deepseek-chat"
  "The model to use for LLM calls. Can be overridden per-session or via the --model CLI flag.")

(defvar *token-readers* nil
  "Ordered list of functions for reading API tokens. Each function accepts a provider name
   (string, e.g. \"deepseek\") and returns the token string or NIL if not found.
   Readers are tried in order; the first non-NIL result is used.
   Default readers are set in codabrus/main. Users may push custom readers
   (e.g. macOS Keychain, Vault) from .local-config.lisp or ~/.codabrus/config.lisp.")
