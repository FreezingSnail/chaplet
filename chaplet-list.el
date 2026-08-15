;;; chaplet-list.el --- tabulated-list bead browser: views + filters -*- lexical-binding: t; -*-

;; The bead table.  Derived from `tabulated-list-mode'.  Renders bead alists
;; from `chaplet-bd-list' / `chaplet-bd-query' into a sortable table with
;; switchable views and type/label filters.

(require 'chaplet-bd)
(require 'chaplet-graph)
(require 'tabulated-list)
(require 'chaplet-face)
(require 'chaplet-bar)
(require 'cl-lib)

;;; Views

(defvar chaplet-list--views
  '((inbox       . "status=deferred AND label=staged")
    (open        . "status=open")
    (in-progress . "status=in_progress")
    (blocked     . "status=blocked")
    (closed      . "status=closed")
    (all         . nil))
  "Alist of view symbol -> bd query expression (nil = unfiltered all).")

(defvar-local chaplet-list--current-view 'inbox
  "The view shown in the current `chaplet-list-mode' buffer.")

(defvar-local chaplet-list--filters nil
  "Active filters alist (keyword . value) for the current buffer.")

(defvar chaplet-list--format
  [("ID" 12) ("Type" 10) ("State" 12) ("P" 3) ("Staged" 7) ("Title" 60)]
  "Column format for `chaplet-list-mode'.")

(defun chaplet-list--view-query (view)
  "Return the bd query expression for VIEW, or nil for the all view."
  (cdr (assq view chaplet-list--views)))

(defun chaplet-list--staged-p (bead)
  "Return non-nil if BEAD is staged: status=deferred AND label=staged.
`bd list --json' does not hydrate labels; when labels are absent, fall
back to status=deferred as a documented approximation."
  (and (string= (alist-get 'status bead) "deferred")
       (let ((labels (alist-get 'labels bead)))
         (or (not (consp labels))
             (member "staged" labels)))))

(defun chaplet-list--filters->query (base filters)
  "Append FILTERS alist as `field=value' clauses to BASE query expr."
  (let ((clauses (delq nil (list base))))
    (dolist (f filters)
      (pcase f
        (`(:type . ,v)  (push (format "type=%s" v) clauses))
        (`(:label . ,v) (push (format "label=%s" v) clauses))
        (_ nil)))
    (mapconcat #'identity (nreverse clauses) " AND ")))

(defun chaplet-list--fetch (view)
  "Return the list of bead alists for VIEW, honoring active filters."
  (let ((query (chaplet-list--view-query view)))
    (if query
        (chaplet-bd-query (chaplet-list--filters->query query chaplet-list--filters))
      (chaplet-bd-list (append '((:all . t)) chaplet-list--filters)))))

(defun chaplet-list--priority-dot (priority)
  "Return the priority display cell for PRIORITY (number or nil).
A dot (● for high, · for medium/low) plus the priority number,
propertized with the matching priority face; \"\" when PRIORITY is nil."
  (if (null priority)
      ""
    (let* ((p (if (stringp priority) (string-to-number priority) priority))
           (dot (if (>= p 2) "●" "·")))
      (propertize (concat dot (number-to-string p))
                  'face (chaplet-priority-face p)))))

(defun chaplet-list--entry (bead)
  "Return a tabulated-list entry (ID . [ID TYPE STATE P STAGED TITLE]) for BEAD.
Cells are propertized with `chaplet-face' faces: ID → `chaplet-id',
State → pill face, P → priority dot+number, Type → type face, Staged → ✔."
  (let ((id (or (alist-get 'id bead) ""))
        (type (or (alist-get 'issue_type bead) ""))
        (status (or (alist-get 'status bead) ""))
        (priority (alist-get 'priority bead)))
    (list id
          (vector
           (propertize id 'face 'chaplet-id)
           (propertize type 'face (chaplet-type-face type))
           (propertize status 'face (chaplet-state-face status))
           (chaplet-list--priority-dot priority)
           (if (chaplet-list--staged-p bead)
               (propertize "✔" 'face 'chaplet-staged)
             "")
           (or (alist-get 'title bead) "")))))

(defun chaplet-list--modeline ()
  "Return a mode-line string for the chaplet bead browser.
Format: \"chaplet <view> · <n> beads · <o> open · <b> blocked\".
Counts are derived from the current `tabulated-list-entries' (state = col 3)."
  (let ((rows (mapcar #'cadr tabulated-list-entries)))
    (format "chaplet %s · %d beads · %d open · %d blocked"
            chaplet-list--current-view
            (length rows)
            (cl-count "open" rows
                      :key (lambda (r) (substring-no-properties (aref r 2)))
                      :test #'string=)
            (cl-count "blocked" rows
                      :key (lambda (r) (substring-no-properties (aref r 2)))
                      :test #'string=))))

(defvar chaplet-list--bar-specs
  '(("v" . "view switch")
    ("s" . "graph")
    ("?" . "actions")
    ("RET" . "open")
    ("q" . "quit")
    ("mouse-1" . "open"))
  "Keybinding reference entries for the list buffer bar.
KEY-STRING entries are checked against `chaplet-list-mode-map' before
being listed, so the bar mirrors the real bindings.")

(defun chaplet-list--buffer-name (view)
  "Return the buffer name for VIEW."
  (format "*chaplet:%s*" view))

(defun chaplet-list--show-raw (id)
  "Display raw `bd show ID' output in a buffer (fallback when detail absent)."
  (let* ((result (chaplet-bd--invoke (list "show" id)))
         (buf (get-buffer-create (format "*chaplet:show %s*" id))))
    (with-current-buffer buf
      (erase-buffer)
      (insert (cdr result)))
    (switch-to-buffer buf)))

;;; Mode

(defun chaplet-list-refresh ()
  "Re-run the current view's query and re-render the table."
  (interactive)
  (setq tabulated-list-entries
        (mapcar #'chaplet-list--entry
                (chaplet-list--fetch chaplet-list--current-view)))
  (tabulated-list-init-header)
  (tabulated-list-print))

(defun chaplet-list-open (id)
  "Open bead ID via `chaplet-detail' when present; else raw `bd show'."
  (interactive (list (tabulated-list-get-id)))
  (if (fboundp 'chaplet-detail)
      (chaplet-detail id)
    (chaplet-list--show-raw id)))

(defun chaplet-list-set-view (name)
  "Switch the bead browser to view NAME (a symbol)."
  (interactive
   (list (intern
          (completing-read
           "View: "
           (mapcar (lambda (v) (symbol-name (car v))) chaplet-list--views)))))
  (switch-to-buffer (chaplet-list--buffer-name name))
  (unless (eq major-mode 'chaplet-list-mode)
    (chaplet-list-mode))
  (setq chaplet-list--current-view name)
  (chaplet-list-refresh))

(defun chaplet-list-filter (type label)
  "Filter the current view by TYPE and/or LABEL (strings, nil to clear).
Both filters are composed into the view's bd query (server-side)."
  (interactive
   (list (read-string "Type (blank = any): ")
         (read-string "Label (blank = any): ")))
  (setq chaplet-list--filters
        (delq nil (list (and (not (string-empty-p type)) (cons :type type))
                        (and (not (string-empty-p label)) (cons :label label)))))
  (chaplet-list-refresh))

(define-derived-mode chaplet-list-mode tabulated-list-mode "Chaplet"
  "Major mode for browsing bd beads in a sortable table.
\\{chaplet-list-mode-map}"
  (setq tabulated-list-format chaplet-list--format)
  (setq tabulated-list-padding 2)
  (setq tabulated-list-sort-key '("ID" . nil))
  (add-hook 'tabulated-list-revert-hook #'chaplet-list-refresh nil t)
  (hl-line-mode 1)
  (setq mode-line-process '(:eval (chaplet-list--modeline)))
  (face-remap-add-relative 'header-line '(chaplet-header header-line))
  (setq-local chaplet-bar--map chaplet-list-mode-map)
  (setq-local chaplet-bar--specs chaplet-list--bar-specs)
  (setq-local chaplet-bar--extra nil)
  (chaplet-bar--install)
  (chaplet-list-refresh))

(defun chaplet-list--bind (key cmd)
  "Bind KEY to CMD in `chaplet-list-mode-map', evil-normal aware."
  (define-key chaplet-list-mode-map key cmd)
  ;; NOTE: use the evil-define-key* *function* (not the evil-define-key
  ;; macro) so this file byte-compiles safely when evil isn't loaded.
  ;; `fboundp' is true for macros, which would otherwise compile to a
  ;; function call and signal `invalid-function' at runtime.
  (when (and (featurep 'evil) (fboundp 'evil-define-key*))
    (evil-define-key* 'normal chaplet-list-mode-map key cmd)))

(chaplet-list--bind (kbd "RET") #'chaplet-list-open)
(chaplet-list--bind (kbd "v") #'chaplet-list-set-view)
(chaplet-list--bind (kbd "s") #'chaplet-graph)
(chaplet-list--bind (kbd "q") #'quit-window)
(define-key chaplet-list-mode-map [mouse-1] #'chaplet-list-open)

;;;###autoload
(defun chaplet-list ()
  "Open the chaplet bead browser on the inbox (staged) view."
  (interactive)
  (chaplet-list-set-view 'inbox))

(provide 'chaplet-list)
;;; chaplet-list.el ends here
