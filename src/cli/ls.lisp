(uiop:define-package #:codabrus/cli/ls
  (:use #:cl)
  (:import-from #:defmain
                #:defcommand)
  (:import-from #:codabrus/cli/main
                #:main)
  (:import-from #:codabrus/session-store
                #:list-sessions))
(in-package #:codabrus/cli/ls)


(defun %frontmatter-value (alist key &optional default)
  (let ((pair (assoc key alist)))
    (if pair (cdr pair) default)))


(defun %truncate (str max-len)
  (if (> (length str) max-len)
      (concatenate 'string (subseq str 0 (- max-len 3)) "...")
      str))


(defcommand (main ls) ()
  "Show sessions with metadata."
  (let ((sessions (list-sessions)))
    (if (null sessions)
        (format t "No sessions found.~%")
        (progn
          (format t "~36A ~30A ~8A ~10A ~20A~%"
                  "SESSION-ID" "PROJECT" "TOKENS" "COST" "UPDATED")
          (format t "~36,,,'-A ~30,,,'-A ~8,,,'-A ~10,,,'-A ~20,,,'-A~%"
                  "-" "-" "-" "-" "-")
          (dolist (fm sessions)
            (let ((id (%truncate (%frontmatter-value fm :id "unknown") 36))
                  (project (%truncate (%frontmatter-value fm :project-dir "") 30))
                  (tokens (parse-integer (%frontmatter-value fm :tokens-in "0")))
                  (cost (let ((*read-eval* nil))
                          (read-from-string (%frontmatter-value fm :total-cost-usd "0.0"))))
                  (updated (%frontmatter-value fm :updated-at "")))
              (format t "~36A ~30A ~8D $~9,4F ~20A~%"
                      id project tokens cost updated)))))))
