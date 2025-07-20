(uiop:define-package #:codabrus
  (:use #:cl)
  (:import-from #:40ants-ai-agents/ai-agent
                #:ai-agent)
  (:import-from #:codabrus/vars
                #:*project-dir*)
  (:import-from #:40ants-ai-agents/user-message
                #:user-message)
  (:import-from #:40ants-ai-agents/state
                #:state)
  (:import-from #:codabrus/tools/search
                #:search-file)
  (:import-from #:40ants-ai-agents/generics
                #:add-message)
  (:import-from #:codabrus/tools/read-file
                #:read-file)
  (:nicknames #:codabrus/core))
(in-package #:codabrus)


(defparameter *system-prompt*
  "You are a code assistant.")


(defun test-ai (request &optional prev-state)
  (let* ((*project-dir* (or (probe-file "~/projects/ai/aider/")
                            (error "Aider folder not found")))
         (state (cond
                  (prev-state
                   (add-message prev-state
                                (user-message request)))
                  (t
                   (state (list (user-message request))))))
         (agent (ai-agent *system-prompt* :tools '(search-file
                                                   read-file)))
         (new-state (40ants-ai-agents/generics:process agent state)))
    (values
     new-state
     (first (40ants-ai-agents/state:state-messages new-state)))))
