;;; chaplet-bd.el --- bd CLI bridge (JSON reads + subcommand writes) -*- lexical-binding: t; -*-

;; The ONLY module that talks to the `bd` CLI.
;; Reads (`list`/`query`/`show`/`graph`) use `--json` and return parsed
;; elisp (JSON -> alists).  Writes execute bd subcommands and return t/nil
;; (or the new id for `create`).

(require 'cl-lib)
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
Return a cons cell (EXIT-CODE . STDOUT).  STDERR is discarded.

ARGS must be all strings.  A nil element (typically a missing bead id from
a command run with point off a row) reaches `call-process' as a raw
`wrong-type-argument' the user cannot act on, so it is rejected here with a
readable `user-error' instead."
  (unless (and (listp args) (cl-every #'stringp args))
    (user-error "chaplet: incomplete bd command (missing argument): %S" args))
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
        dependencies defer_until design acceptance created_at updated_at
        parent)
  "Fields present in a normalized bead alist, in order.")

(defun chaplet-bd--normalize (parsed)
  "Normalize PARSED (JSON object alist) into a flat bead alist.
Keys are symbols from `chaplet-bd--fields'; missing fields default to nil.
Real bd reports acceptance criteria as `acceptance_criteria', and
dependencies as objects (see `chaplet-bd--normalize-deps')."
  (let (bead)
    (dolist (f chaplet-bd--fields bead)
      (push (cons f (alist-get f parsed)) bead))
    (setq bead (nreverse bead))
    (when (and (null (alist-get 'acceptance bead))
               (alist-get 'acceptance_criteria parsed))
      (setf (alist-get 'acceptance bead) (alist-get 'acceptance_criteria parsed)))
    (setf (alist-get 'dependencies bead)
          (chaplet-bd--normalize-deps (alist-get 'dependencies bead)))
    bead))

(defun chaplet-bd--normalize-deps (deps)
  "Normalize DEPS into a list of id strings.
Real bd reports each dependency as an object
`((issue_id . ID) (depends_on_id . DEP) (type . ...) ...)';
the bead depends on DEP.  Older/simpler sources report plain id strings,
which pass through unchanged."
  (mapcar (lambda (d)
            (if (consp d)
                (alist-get 'depends_on_id d)
              d))
          deps))

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

;;; Views

(defconst chaplet-staged-label "staged"
  "Label marking a bead as staged (deferred, awaiting review).
The inbox view is the set of staged beads; approving one must strip
this label so it leaves the inbox even if it stays deferred.")

(defconst chaplet-human-label "human"
  "Label marking a bead as requiring human input.")

(defconst chaplet-bd--views
  `((inbox . ((:status . "deferred") (:label . ,chaplet-staged-label)))
    (human . ((:label . ,chaplet-human-label)))
    (deferred . ((:status . "deferred")))
    (open . ((:status . "open")))
    (in-progress . ((:status . "in_progress")))
    (blocked . ((:status . "blocked")))
    (closed . ((:status . "closed")))
    (all . ((:all . t))))
  "Canonical view symbol → filters alist.")

(defun chaplet-bd--view-filters (view)
  "Return the filters alist for VIEW (a symbol in `chaplet-bd--views')."
  (alist-get view chaplet-bd--views))

(defun chaplet-bd--view-names ()
  "Return the list of known view symbols."
  (mapcar #'car chaplet-bd--views))

(defun chaplet-bd--filters->expr (filters)
  "Convert FILTERS alist into a `bd query' expression string.
Value filters (:status/:type/:label/:priority) emit \"key=value\";
boolean filters (:all/:ready/:deferred) are skipped.  Clauses are
joined by \" AND \"."
  (mapconcat #'identity
             (delq nil
                   (mapcar (lambda (f)
                             (pcase f
                               (`(:status . ,v)   (format "status=%s" v))
                               (`(:type . ,v)     (format "type=%s" v))
                               (`(:label . ,v)    (format "label=%s" v))
                               (`(:priority . ,v) (format "priority=%s" v))
                               (`(:all . ,_) nil)
                               (`(:ready . ,_) nil)
                               (`(:deferred . ,_) nil)
                               (_ (error "chaplet-bd: unknown filter %S" f))))
                           filters))
             " AND "))

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

(defun chaplet-bd-graph-data (&optional filters)
  "Return bead alists for the graph scope.
FILTERS is a filters alist forwarded to `chaplet-bd-list'.
Each bead alist carries `dependencies' (list of id strings)."
  (chaplet-bd-list filters))

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

(defun chaplet-bd-label-remove (id label)
  "Remove LABEL from bead ID.  Return t on success."
  (chaplet-bd--ok (list "label" "remove" id label)))

(defun chaplet-bd-close (id &optional reason)
  "Close bead ID, optionally recording REASON.  Return t on success."
  (chaplet-bd--ok (append (list "close" id)
                          (and (not (string-empty-p (or reason "")))
                               (list "--reason" reason)))))

(defun chaplet-bd-reopen (id &optional reason)
  "Reopen bead ID, optionally recording REASON.  Return t on success."
  (chaplet-bd--ok (append (list "reopen" id)
                          (and (not (string-empty-p (or reason "")))
                               (list "--reason" reason)))))

(defun chaplet-bd-claim (id)
  "Atomically claim bead ID.  Return t on success."
  (chaplet-bd--ok (list "update" id "--claim")))

(defun chaplet-bd-assign (id assignee)
  "Assign bead ID to ASSIGNEE (empty string unassigns)."
  (chaplet-bd--ok (list "assign" id assignee)))

(defun chaplet-bd-priority (id priority)
  "Set bead ID to PRIORITY (0–4).  Return t on success."
  (chaplet-bd--ok (list "priority" id (format "%s" priority))))

(defun chaplet-bd-update (id field value)
  "Set mutable bead FIELD to VALUE.  Return t on success.
FIELD is one of title, description, type, design, or acceptance."
  (let ((flag (pcase field
                ('title "--title")
                ('description "--description")
                ('type "--type")
                ('design "--design")
                ('acceptance "--acceptance")
                (_ (error "chaplet-bd: unsupported update field %S" field)))))
    (chaplet-bd--ok (list "update" id flag value))))

(defun chaplet-bd-dependency-add (id depends-on)
  "Make bead ID depend on DEPENDS-ON.  Return t on success."
  (chaplet-bd--ok (list "dep" "add" id depends-on)))

(defun chaplet-bd-dependency-remove (id depends-on)
  "Remove ID's dependency on DEPENDS-ON.  Return t on success."
  (chaplet-bd--ok (list "dep" "remove" id depends-on)))

(defun chaplet-bd-duplicate (id canonical)
  "Mark bead ID as a duplicate of CANONICAL.  Return t on success."
  (chaplet-bd--ok (list "duplicate" id "--of" canonical)))

(defun chaplet-bd-supersede (id replacement)
  "Mark bead ID as superseded by REPLACEMENT.  Return t on success."
  (chaplet-bd--ok (list "supersede" id "--with" replacement)))

(defun chaplet-bd-human-respond (id response)
  "Respond to human bead ID and close it.  Return t on success."
  (chaplet-bd--ok (list "human" "respond" id "--response" response)))

(defun chaplet-bd-human-dismiss (id &optional reason)
  "Dismiss human bead ID, optionally recording REASON.  Return t on success."
  (chaplet-bd--ok (append (list "human" "dismiss" id)
                          (and (not (string-empty-p (or reason "")))
                               (list "--reason" reason)))))

(provide 'chaplet-bd)
;;; chaplet-bd.el ends here
