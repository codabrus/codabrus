(uiop:define-package #:codabrus/tools/search
  (:use #:cl)
  (:import-from #:completions
                #:defun-tool)
  (:import-from #:codabrus/vars
                #:*project-dir*)
  (:import-from #:serapeum
                #:fmt
                #:length<=)
  (:import-from #:log)
  (:export #:search-file))
(in-package #:codabrus/tools/search)


(defun %parse-filenames (comma-separated)
  (loop for item in (str:split "," comma-separated)
        for trimmed = (str:trim item)
        unless (or (string= "." trimmed)
                   (string= "./" trimmed)
                   (string= "/" trimmed))
          collect trimmed))


;; На самом деле мне нужно добавить функционал по игнорированию, чтобы можно было исключать термины и игнорировать некоторые файлы или директории. 
(defun %search-file (term search-in ignore-files)
  (log:info "Searching" term search-in ignore-files)
  (let* ((command (append
                   (list (namestring
                          (or (probe-file "~/.nix-profile/bin/rg")
                              (probe-file "/usr/bin/rg")
                              (error "Ripgrep command line app not found")))
                         "--ignore-case")
                   (when (and search-in
                              (not (str:emptyp search-in)))
                     (loop for item in (%parse-filenames search-in)
                           append (list "--glob" item)))
                   (when (and ignore-files
                              (not (str:emptyp ignore-files)))
                     (loop for item in (%parse-filenames ignore-files)
                           append (list "--glob"
                                        (fmt "!~A" item))))
                   (list term
                         ;; (str:trim-right (uiop:native-namestring *project-dir*)
                         ;;                 :char-bag "/")
                         )))
         (output (uiop:with-current-directory (*project-dir*)
                   (uiop:run-program command
                                     :output '(:string :stripped t)
                                     :error-output :output))))
    (cond
      ((str:emptyp output)
       "NOT-FOUND")
      (t
       (let ((length-limit 2000))
         (cond
           ((length<= length-limit output)
            (fmt "~A

MORE FILES WERE FOUND. Try to give a more specific TERM to search."
                 (str:shorten length-limit output)))
           
           (t
            output)))))))


(defun-tool search-file ((term string "TERM to search.")
                         (search-in string "Comma separated list of files or directories to search in. If not given, then search will be made in the whole current project.")
                         (ignore-files string "Comma separated list of files to ignore."))
  "Searches given term in all project files. Term could be a class name, function name or some other word.

For example if we searched term \"class.*CoderPrompts\" and something was found, a text of following format will be returned:

```

/Users/art/projects/ai/aider/aider/coders/udiff_prompts.py
7:class UnifiedDiffPrompts(CoderPrompts):

/Users/art/projects/ai/aider/aider/coders/help_prompts.py
6:class HelpPrompts(CoderPrompts):

/Users/art/projects/ai/aider/tests/fixtures/chat-history.md
308:│class AskPrompts(CoderPrompts):
471:│class CoderPrompts:
544:│class EditBlockFunctionPrompts(CoderPrompts):

```

These sections might repeat if term was found in multiple files.

Use SEARCH-IN argument only when you need narrow down your search. In all other cases, pass an empty string.

If there are `MORE FILES WERE FOUND` at the end of response, then there are too many
results on the given TERM. Try to ask more specific term to narrow down search results.

If nothing was found, returns text `NOT-FOUND`.
" 
  (let ((response (%search-file term search-in ignore-files)))
    (values response)))
