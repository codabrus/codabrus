(uiop:define-package #:codabrus/session-store
  (:use #:cl)
  (:import-from #:codabrus/session
                #:session
                #:session-id
                #:session-project-dir
                #:session-model
                #:session-state
                #:session-tokens-in
                #:session-tokens-out
                #:session-total-cost-usd
                #:session-created-at
                #:session-updated-at
                #:make-session)
  (:import-from #:40ants-ai-agents/state
                #:state
                #:state-messages)
  (:import-from #:40ants-ai-agents/user-message
                #:user-message
                #:user-message-text)
  (:import-from #:40ants-ai-agents/ai-message
                #:ai-message
                #:ai-message-text)
  (:import-from #:log)
  (:export #:*sessions-dir*
           #:save-session
           #:load-session
           #:list-sessions
           #:delete-session
           #:session-file-path))
(in-package #:codabrus/session-store)


(defvar *sessions-dir*
  (merge-pathnames (make-pathname :directory '(:relative ".cache" "codabrus" "sessions"))
                   (user-homedir-pathname))
  "Directory where session files are stored. Default: ~/.cache/codabrus/sessions/")


(defun session-file-path (session-id)
  "Return the pathname for SESSION-ID's markdown file."
  (merge-pathnames (make-pathname :name session-id :type "md")
                   *sessions-dir*))


(defun ensure-sessions-dir ()
  "Create *sessions-dir* if it doesn't exist."
  (ensure-directories-exist *sessions-dir*))


(defun %split-lines (text)
  "Split TEXT into a list of lines (without newline characters)."
  (with-input-from-string (s text)
    (loop for line = (read-line s nil nil)
          while line collect line)))


(defun %serialize-frontmatter (session)
  "Serialize session metadata as a YAML-like frontmatter string."
  (with-output-to-string (s)
    (format s "---~%")
    (format s "id: ~A~%" (session-id session))
    (format s "project-dir: ~S~%" (namestring (session-project-dir session)))
    (format s "model: ~A~%" (session-model session))
    (format s "tokens-in: ~A~%" (session-tokens-in session))
    (format s "tokens-out: ~A~%" (session-tokens-out session))
    (format s "total-cost-usd: ~A~%" (session-total-cost-usd session))
    (format s "created-at: ~S~%" (session-created-at session))
    (format s "updated-at: ~S~%" (session-updated-at session))
    (format s "---~%")))


(defun %serialize-body (session)
  "Serialize session messages as markdown sections."
  (let ((messages (when (session-state session)
                    (state-messages (session-state session)))))
    (if messages
        (with-output-to-string (s)
          (loop
            for msg in (reverse messages)
            for role = (cond ((typep msg 'user-message) "User")
                             ((typep msg 'ai-message) "Assistant")
                             (t nil))
            when role
              do (format s "~%~%## ~A~%~%" role)
                 (let ((text (if (typep msg 'user-message)
                                 (user-message-text msg)
                                 (ai-message-text msg))))
                   (write-string text s)
                   (terpri s))))
        "")))


(defun %parse-frontmatter (lines)
  "Parse YAML-like frontmatter from LINES. Returns an alist of key-value pairs.
Expects LINES to start with '---', end at the next '---'."
  (unless (and lines (string= (first lines) "---"))
    (error "Missing opening frontmatter delimiter"))
  (let ((result nil)
        (in-frontmatter nil))
    (dolist (line (rest lines))
      (when (string= line "---")
        (return))
      (setf in-frontmatter t)
      (let ((colon-pos (position #\: line)))
        (when (and colon-pos (> (length line) colon-pos))
          (let* ((key (string-trim " " (subseq line 0 colon-pos)))
                 (value-raw (string-trim " " (subseq line (1+ colon-pos))))
                 (value (if (and (> (length value-raw) 1)
                                 (char= (char value-raw 0) #\"))
                            (read-from-string value-raw)
                            value-raw)))
            (push (cons (intern (string-upcase key) :keyword) value)
                  result)))))
    (unless in-frontmatter
      (error "Missing closing frontmatter delimiter"))
    (nreverse result)))


(defun %find-body-start (lines)
  "Find the index of the first line after the closing '---'."
  (let ((saw-first nil))
    (loop for i from 0
          for line in lines
          when (and saw-first (string= line "---"))
            do (return-from %find-body-start (1+ i))
          when (string= line "---")
            do (setf saw-first t)))
  (length lines))


(defun %parse-body-messages (lines)
  "Parse ## User and ## Assistant sections from LINES.
Returns a list of message instances in chronological order."
  (let ((body-lines (nthcdr (%find-body-start lines) lines))
        (messages nil)
        (current-role nil)
        (current-text-lines nil))
    (flet ((flush-section ()
             (when (and current-role current-text-lines)
               (let ((text (string-trim '(#\Newline #\Space #\Tab)
                                        (format nil "~{~A~%~}" (nreverse current-text-lines)))))
                 (cond
                   ((string= current-role "User")
                    (push (user-message text) messages))
                   ((string= current-role "Assistant")
                    (push (ai-message text) messages))))
               (setf current-text-lines nil))))
      (dolist (line body-lines)
        (let ((stripped (string-trim " " line)))
          (cond
            ((and (>= (length stripped) 3)
                  (string= (subseq stripped 0 3) "## "))
             (flush-section)
             (setf current-role (string-trim " " (subseq stripped 3))))
            (t
             (when current-role
               (push line current-text-lines))))))
      (flush-section))
    (reverse messages)))


(defun %frontmatter-value (alist key &optional default)
  "Lookup KEY in frontmatter ALIST, return DEFAULT if not found."
  (let ((pair (assoc key alist)))
    (if pair (cdr pair) default)))


(defun save-session (session)
  "Serialize SESSION to a markdown file in *sessions-dir*."
  (ensure-sessions-dir)
  (let* ((path (session-file-path (session-id session)))
         (content (concatenate 'string
                               (%serialize-frontmatter session)
                               (%serialize-body session))))
    (with-open-file (f path :direction :output
                            :if-exists :supersede
                            :if-does-not-exist :create)
      (write-string content f))
    (log:info "Session ~A saved to ~A" (session-id session) path)
    path))


(defun load-session (session-id)
  "Load a session from its markdown file. Returns a session instance."
  (let* ((path (session-file-path session-id))
         (body (uiop:read-file-string path))
         (lines (%split-lines body))
         (frontmatter (%parse-frontmatter lines))
         (messages (%parse-body-messages lines))
         (project-dir (pathname (%frontmatter-value frontmatter :project-dir))))
    (make-session project-dir
                  :id (%frontmatter-value frontmatter :id)
                  :model (%frontmatter-value frontmatter :model "deepseek-chat")
                  :state (when messages (state messages))
                  :tokens-in (parse-integer (%frontmatter-value frontmatter :tokens-in "0"))
                  :tokens-out (parse-integer (%frontmatter-value frontmatter :tokens-out "0"))
                  :total-cost-usd (read-from-string
                                   (%frontmatter-value frontmatter :total-cost-usd "0.0d0"))
                  :created-at (%frontmatter-value frontmatter :created-at)
                  :updated-at (%frontmatter-value frontmatter :updated-at))))


(defun list-sessions ()
  "Return a list of alists, one per session, with metadata from frontmatters."
  (ensure-sessions-dir)
  (let ((files (directory (merge-pathnames "*.md" *sessions-dir*)))
        (result nil))
    (dolist (f files)
      (handler-case
          (let* ((body (uiop:read-file-string f))
                 (lines (%split-lines body))
                 (fm (%parse-frontmatter lines)))
            (push (cons :file (namestring f)) fm)
            (push fm result))
        (error (e)
          (log:warn "Skipping ~A: ~A" f e))))
    (sort result #'string<
          :key (lambda (fm) (%frontmatter-value fm :updated-at "")))))


(defun delete-session (session-id)
  "Delete the session file for SESSION-ID."
  (let ((path (session-file-path session-id)))
    (when (probe-file path)
      (delete-file path)
      (log:info "Session ~A deleted" session-id)
      t)))
