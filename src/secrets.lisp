(uiop:define-package #:codabrus/secrets
  (:use #:cl)
  (:import-from #:yason)
  (:import-from #:codabrus/vars
                #:*token-readers*)
  (:export #:secrets-json-reader
           #:env-var-reader
           #:keychain-reader
           #:read-token))
(in-package #:codabrus/secrets)


(defun secrets-json-reader (provider)
  "Read token for PROVIDER from ~/.config/codabrus/secrets.json.
   Returns nil if the file does not exist or the provider key is absent."
  (let ((secrets-file (merge-pathnames ".config/codabrus/secrets.json"
                                       (user-homedir-pathname))))
    (when (probe-file secrets-file)
      (with-open-file (f secrets-file)
        (let ((data (yason:parse f)))
          (gethash provider data))))))


(defun env-var-reader (provider)
  "Read token for PROVIDER from an environment variable.
   Convention: DEEPSEEK -> DEEPSEEK_API_TOKEN."
  (uiop:getenv (concatenate 'string
                             (string-upcase provider)
                             "_API_TOKEN")))


(defun keychain-reader (provider)
  "Read token for PROVIDER from the macOS Keychain.
   Looks for a generic password with service name \"codabrus-<provider>\".
   Returns nil on non-macOS platforms or if the entry does not exist."
  #+darwin
  (let ((token (uiop:run-program
                (list "security" "find-generic-password"
                      "-a" (uiop:getenv "USER")
                      "-s" (concatenate 'string "codabrus-" provider)
                      "-w")
                :output :string
                :ignore-error-status t)))
    (when token
      (string-trim '(#\Space #\Newline #\Return #\Tab) token)))
  #-darwin
  nil)


;; Set default readers. Users may push custom readers from
;; .local-config.lisp or ~/.codabrus/config.lisp before read-token is called.
(setf *token-readers* (list #'secrets-json-reader
                             #'keychain-reader
                             #'env-var-reader))


(defun read-token (provider)
  "Try each reader in *TOKEN-READERS* in order; return the first non-empty token."
  (dolist (reader *token-readers*)
    (let ((token (funcall reader provider)))
      (when (and token (plusp (length token)))
        (return token)))))
