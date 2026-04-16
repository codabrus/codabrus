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
  (:import-from #:codabrus/message
                #:message
                #:message-role
                #:message-parts
                #:message-text
                #:text-part
                #:text-part-content
                #:tool-call-part
                #:tool-call-part-tool-name
                #:tool-call-part-call-id
                #:tool-call-part-raw-args
                #:tool-result-part
                #:tool-result-part-call-id
                #:tool-result-part-output
                #:step-end-part
                #:step-end-part-finish-reason
                #:step-end-part-tokens-in
                #:step-end-part-tokens-out
                #:step-end-part-cost-usd
                #:make-text-part
                #:make-tool-call-part
                #:make-tool-result-part
                #:make-step-end-part
                #:make-user-message
                #:make-assistant-message)
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


(defun %serialize-part (part s)
  (typecase part
    (text-part
     (write-string (text-part-content part) s))
    (tool-call-part
     (format s "### Tool Call: ~A (~A)~%~%```json~%~A~%```~%"
             (tool-call-part-tool-name part)
             (tool-call-part-call-id part)
             (tool-call-part-raw-args part)))
    (tool-result-part
     (format s "### Tool Result (~A)~%~%~A~%"
             (tool-result-part-call-id part)
             (tool-result-part-output part)))
    (step-end-part
     (format s "### Step End~%~A tokens: ~A in / ~A out | cost: $~,3F~%"
             (step-end-part-finish-reason part)
             (step-end-part-tokens-in part)
             (step-end-part-tokens-out part)
             (step-end-part-cost-usd part)))))


(defun %serialize-body (session)
  "Serialize session messages as markdown sections with parts."
  (let ((messages (when (session-state session)
                    (state-messages (session-state session)))))
    (if messages
        (with-output-to-string (s)
          (loop
            for msg in (reverse messages)
            when (typep msg 'message)
              do (format s "~%~%## ~(~A~)~%~%" (message-role msg))
                 (dolist (part (message-parts msg))
                   (%serialize-part part s)
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


(defun %parse-tool-call-header (line)
  "Parse '### Tool Call: tool-name (call-id)' from LINE.
Returns (values tool-name call-id) or NIL."
  (let ((prefix "### Tool Call: "))
    (when (and (>= (length line) (length prefix))
               (string= (subseq line 0 (length prefix)) prefix))
      (let* ((rest (subseq line (length prefix)))
             (open-paren (position #\( rest :from-end t))
             (close-paren (position #\) rest :from-end t)))
        (when (and open-paren close-paren)
          (values (string-trim " " (subseq rest 0 open-paren))
                  (string-trim " " (subseq rest (1+ open-paren) close-paren))))))))

(defun %parse-tool-result-header (line)
  "Parse '### Tool Result (call-id)' from LINE.
Returns call-id or NIL."
  (let ((prefix "### Tool Result"))
    (when (and (>= (length line) (length prefix))
               (string= (subseq line 0 (length prefix)) prefix))
      (let ((open-paren (position #\( line))
            (close-paren (position #\) line :from-end t)))
        (when (and open-paren close-paren)
          (string-trim " " (subseq line (1+ open-paren) close-paren)))))))


(defun %parse-body-messages (lines)
  "Parse ## User / ## Assistant sections with parts from LINES.
Returns a list of message instances in chronological order."
  (let ((body-lines (nthcdr (%find-body-start lines) lines))
        (messages nil)
        (current-role nil)
        (current-parts nil)
        (current-text-lines nil)
        (pending-tool-call-name nil)
        (pending-tool-call-id nil)
        (pending-tool-call-args nil))
    (flet ((flush-text ()
             (when current-text-lines
               (let ((text (string-trim '(#\Newline #\Space #\Tab)
                                        (format nil "~{~A~%~}" (nreverse current-text-lines)))))
                 (unless (string= text "")
                   (push (make-text-part text) current-parts)))
               (setf current-text-lines nil)))
           (flush-pending-tool-call ()
             (when pending-tool-call-name
               (push (make-tool-call-part pending-tool-call-name
                                          pending-tool-call-id
                                          (or pending-tool-call-args "{}"))
                     current-parts)
               (setf pending-tool-call-name nil
                     pending-tool-call-id nil
                     pending-tool-call-args nil)))
           (flush-section ()
             (flush-pending-tool-call)
             (flush-text)
             (when (and current-role current-parts)
               (let ((role-key (cond ((string-equal current-role "User") :user)
                                     ((string-equal current-role "Assistant") :assistant)
                                     ((string-equal current-role "System") :system))))
                 (when role-key
                   (push (make-instance 'message
                                        :role role-key
                                        :parts (nreverse current-parts)
                                        :created-at "")
                         messages))))
             (setf current-parts nil
                   current-text-lines nil)))
      (dolist (line body-lines)
        (let ((stripped (string-trim " " line)))
          (cond
            ((and (>= (length stripped) 3)
                  (string= (subseq stripped 0 3) "## "))
             (flush-section)
             (setf current-role (string-trim " " (subseq stripped 3))))
            ((and (>= (length stripped) 15)
                  (string= (subseq stripped 0 15) "### Tool Call: "))
             (flush-text)
             (flush-pending-tool-call)
             (multiple-value-bind (name call-id)
                 (%parse-tool-call-header stripped)
               (setf pending-tool-call-name name
                     pending-tool-call-id call-id
                     pending-tool-call-args nil)))
            ((and (>= (length stripped) 16)
                  (string= (subseq stripped 0 16) "### Tool Result "))
             (flush-text)
             (flush-pending-tool-call)
             (let ((call-id (%parse-tool-result-header stripped)))
               (setf current-text-lines nil)
               (let ((text-start (position #\Newline stripped :start 16)))
                 (when text-start
                   (push (make-tool-result-part call-id
                                                (string-trim '(#\Newline #\Space #\Tab)
                                                             (subseq stripped text-start)))
                         current-parts)))))
            ((and pending-tool-call-name
                  (string= stripped "```json"))
             nil)
            ((and pending-tool-call-name
                  (string= stripped "```"))
             (flush-pending-tool-call))
            ((and pending-tool-call-name
                  current-text-lines)
             (setf pending-tool-call-args
                   (if pending-tool-call-args
                       (concatenate 'string pending-tool-call-args #\Newline stripped)
                       stripped)))
            ((and (>= (length stripped) 11)
                  (string= (subseq stripped 0 11) "### Step End"))
             (flush-text)
             (flush-pending-tool-call))
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
