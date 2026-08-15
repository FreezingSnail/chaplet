;;; chaplet-bd.el --- bd CLI bridge (JSON reads + subcommand writes) -*- lexical-binding: t; -*-

;; The ONLY module that talks to the `bd` CLI.
;; Reads (`list`/`query`/`show`/`graph`) use `--json` and return parsed
;; elisp (JSON -> alists).  Writes execute bd subcommands and return t/nil
;; (or the new id for `create`).

(require 'json)
(require 'project)

;;; Injection seam (tests override this)

(defvar chaplet-bd-program "bd"
  "Path (or name) of the bd executable.  Override for tests.")

;;; Core

(defun chaplet-bd--root ()
  "Return the project root directory, or `default-directory' as fallback."
  (let ((proj (project-current)))
    (if proj
        (expand-file-name (project-root proj))
      (expand-file-name default-directory))))

(defun chaplet-bd--invoke (args)
  "Run `chaplet-bd-program' with ARGS, scoped to `-C ROOT'.
Return a cons cell (EXIT-CODE . STDOUT).  STDERR is discarded."
  (with-temp-buffer
    (let* ((root (chaplet-bd--root))
           (default-directory root)
           (exit-code
            (condition-case nil
                (apply #'call-process chaplet-bd-program nil t nil
                       (append (list "-C" root) args))
              (file-missing 127))))
      (cons exit-code (buffer-string)))))

(defun chaplet-bd--parse (stdout)
  "Parse STDOUT (JSON) into a list of JSON objects (alists).
Handles `[]', `null', and a single bare object."
  (let ((s (string-trim stdout)))
    (cond
     ((or (string-empty-p s) (string= s "null")) nil)
     (t (let ((parsed (json-parse-string s
                                         :object-type 'alist
                                         :array-type 'list
                                         :null-object nil
                                         :false-object nil)))
          (if (string-prefix-p "[" s) parsed (list parsed)))))))

(defconst chaplet-bd--fields
  '(id title description status priority issue_type owner labels
        dependencies defer_until design acceptance created_at updated_at)
  "Fields present in a normalized bead alist, in order.")

(defun chaplet-bd--normalize (parsed)
  "Normalize PARSED (JSON object alist) into a flat bead alist.
Keys are symbols from `chaplet-bd--fields'; missing fields default to nil.
Real bd reports acceptance criteria as `acceptance_criteria'."
  (let (bead)
    (dolist (f chaplet-bd--fields bead)
      (push (cons f (alist-get f parsed)) bead))
    (setq bead (nreverse bead))
    (when (and (null (alist-get 'acceptance bead))
               (alist-get 'acceptance_criteria parsed))
      (setf (alist-get 'acceptance bead) (alist-get 'acceptance_criteria parsed)))
    bead))

;;; Filters -> CLI args

(defun chaplet-bd--filters->args (filters)
  "Convert FILTERS alist (keyword . value) into bd CLI args.
Boolean filters (:all, :ready, :deferred) emit a bare flag when non-nil.
Value filters (:status, :type, :priority, :label, :limit) emit --flag=value."
  (let ((args '()))
    (dolist (f filters (nreverse args))
      (pcase f
        (`(:status . ,v)   (push (concat "--status=" v) args))
        (`(:type . ,v)     (push (concat "--type=" v) args))
        (`(:priority . ,v) (push (concat "--priority=" (format "%s" v)) args))
        (`(:label . ,v)    (push (concat "--label=" v) args))
        (`(:limit . ,v)    (push (concat "--limit=" (format "%s" v)) args))
        (`(:all . ,v)      (when v (push "--all" args)))
        (`(:ready . ,v)    (when v (push "--ready" args)))
        (`(:deferred . ,v) (when v (push "--deferred" args)))
        (_ (error "chaplet-bd: unknown filter %S" f))))))

;;; Reads

(defun chaplet-bd-list (&optional filters)
  "List beads as alists via `bd list --json'.  FILTERS is an alist."
  (let ((result (chaplet-bd--invoke
                 (append '("list" "--json")
                         (chaplet-bd--filters->args filters)))))
    (when (= (car result) 0)
      (mapcar #'chaplet-bd--normalize (chaplet-bd--parse (cdr result))))))

(defun chaplet-bd-query (expr)
  "Query beads via `bd query --json EXPR'.  Return list of bead alists."
  (let ((result (chaplet-bd--invoke (list "query" "--json" expr))))
    (when (= (car result) 0)
      (mapcar #'chaplet-bd--normalize (chaplet-bd--parse (cdr result))))))

(defun chaplet-bd-show (id)
  "Show a single bead via `bd show --json --long ID'.  Return a bead alist."
  (let ((result (chaplet-bd--invoke (list "show" "--json" "--long" id))))
    (when (= (car result) 0)
      (car (mapcar #'chaplet-bd--normalize (chaplet-bd--parse (cdr result)))))))

(defun chaplet-bd-comments (id)
  "List comments on bead ID as alists (author, text, created_at, ...).
Returns nil if bd fails or the bead has no comments."
  (let ((result (chaplet-bd--invoke (list "comments" id "--json"))))
    (when (= (car result) 0)
      (chaplet-bd--parse (cdr result)))))

(defun chaplet-bd-graph-dot (&optional filters)
  "Return dependency graph as DOT string.
FILTERS may carry:
  (:id . \"...\")  — graph one issue via `bd graph --dot ID'.
  (:closed . t)    — include closed items via `bd list --format dot --all'.
Otherwise `bd graph --dot --all' (open issues only)."
  (let* ((id (alist-get :id filters))
         (closed (alist-get :closed filters))
         (args (cond
                (id     (list "graph" "--dot" id))
                (closed (list "list" "--format" "dot" "--all"))
                (t      (list "graph" "--dot" "--all")))))
    (let ((result (chaplet-bd--invoke args)))
      (when (= (car result) 0)
        (cdr result)))))

(defun chaplet-bd-graph-data (&optional include-closed)
  "Return bead alists for the graph scope.
INCLUDE-CLOSED nil → open beads only (`chaplet-bd-list' with nil filters);
non-nil → include closed beads (`chaplet-bd-list' with `((:all . t))').
Each bead alist carries `dependencies' (list of id strings)."
  (chaplet-bd-list (if include-closed '((:all . t)) nil)))

;;; Writes

(defun chaplet-bd--ok (args)
  "Run write subcommand ARGS; return t on exit code 0, else nil."
  (= (car (chaplet-bd--invoke args)) 0))

(defun chaplet-bd-create (title type description)
  "Create a bead; return its id string, or nil on failure."
  (let ((result (chaplet-bd--invoke
                 (list "create" title "-t" type "-d" description "--silent"))))
    (when (= (car result) 0)
      (string-trim (cdr result)))))

(defun chaplet-bd-comment (id text)
  "Add a comment to bead ID.  Return t on success."
  (chaplet-bd--ok (list "comment" id text)))

(defun chaplet-bd-undefer (id)
  "Undefer bead ID (approve).  Return t on success."
  (chaplet-bd--ok (list "undefer" id)))

(defun chaplet-bd-defer (id)
  "Defer bead ID.  Return t on success."
  (chaplet-bd--ok (list "defer" id)))

(defun chaplet-bd-update-design (id design)
  "Set DESIGN notes on bead ID.  Return t on success."
  (chaplet-bd--ok (list "update" id "--design" design)))

(defun chaplet-bd-update-acceptance (id acc)
  "Set ACCEPTANCE criteria on bead ID.  Return t on success."
  (chaplet-bd--ok (list "update" id "--acceptance" acc)))

(defun chaplet-bd-label (id label)
  "Add LABEL to bead ID.  Return t on success."
  (chaplet-bd--ok (list "label" "add" id label)))

(provide 'chaplet-bd)
;;; chaplet-bd.el ends here
