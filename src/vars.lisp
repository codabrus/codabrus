(uiop:define-package #:codabrus/vars
  (:use #:cl)
  (:import-from #:serapeum
                #:defvar-unbound)
  (:export #:*project-dir*
           #:*model*
           #:*token-readers*
           #:*headless-mode*
           #:*allow-execute*
           #:headless-permission-denied
           #:permission-denied-tool-name))
(in-package #:codabrus/vars)


(defvar-unbound *project-dir*
  "An absolute path to the root directory of the current project.")

(defparameter *model* "deepseek-chat"
  "The model to use for LLM calls. Can be overridden per-session or via the --model CLI flag.")

(defvar *token-readers* nil
  "Ordered list of functions for reading API tokens. Each function accepts a provider name
   (string, e.g. \"deepseek\") and returns the token string or NIL if not found.
   Readers are tried in order; the first non-NIL result is used.
   Default readers are set in codabrus/cli/main. Users may push custom readers
   (e.g. macOS Keychain, Vault) from .local-config.lisp or ~/.codabrus/config.lisp.")

(defvar *headless-mode* nil
  "When true, the agent runs without human interaction. Activated by --non-interactive flag
   or when the CI environment variable is set to \"true\". In headless mode, tool calls that
   would normally prompt the user are auto-approved or denied per policy.")

(defvar *allow-execute* nil
  "When true in headless mode, :execute tier tools (e.g. bash) are permitted.
   Activated by --allow-execute flag. Has no effect outside headless mode.")

(define-condition headless-permission-denied (error)
  ((tool-name :initarg :tool-name :reader permission-denied-tool-name))
  (:report (lambda (c s)
             (format s "Tool ~S requires :execute permission, which is denied in headless mode. ~
                        Pass --allow-execute to enable it."
                     (permission-denied-tool-name c)))))
