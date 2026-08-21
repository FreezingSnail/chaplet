;;; chaplet-list.el --- tabulated-list bead browser: views + filters -*- lexical-binding: t; -*-

;; The bead table.  Derived from `tabulated-list-mode'.  Renders bead alists
;; from `chaplet-bd-list' / `chaplet-bd-query' into a sortable table with
;; switchable views and type/label filters.

(require 'chaplet-bd)
(require 'chaplet-graph)
(require 'chaplet-detail)
(require 'tabulated-list)
(require 'chaplet-face)
(require 'chaplet-bar)
(require 'cl-lib)

;;; Views

(defvar-local chaplet-list--current-view 'inbox
  "The view shown in the current `chaplet-list-mode' buffer.")

(defvar-local chaplet-list--filters nil
  "Active filters alist (keyword . value) for the current buffer.")

(defvar chaplet-list--format
  [("ID" 12) ("Type" 10) ("State" 12) ("P" 3) ("Staged" 7) ("Title" 60)]
  "Column format for `chaplet-list-mode'.")

(defun chaplet-list--view-query (view)
  "Return the bd query expression for VIEW, or nil for the all view."
  (if (eq view 'all)
      nil
    (chaplet-bd--filters->expr (chaplet-bd--view-filters view))))

(defun chaplet-list--staged-p (bead)
  "Return non-nil if BEAD is staged: status=deferred AND label=staged.
`bd list --json' does not hydrate labels; when labels are absent, fall
back to status=deferred as a documented approximation."
  (and (string= (alist-get 'status bead) "deferred")
       (let ((labels (alist-get 'labels bead)))
         (or (not (consp labels))
             (member chaplet-staged-label labels)))))

(defun chaplet-list--filters->query (base filters)
  "Append FILTERS alist clauses to BASE query expr, joined by \" AND \"."
  (mapconcat #'identity
             (delete "" (delq nil (list base (chaplet-bd--filters->expr filters))))
             " AND "))

(defun chaplet-list--fetch (view)
  "Return the list of bead alists for VIEW, honoring active filters."
  (let ((filters (append (chaplet-bd--view-filters view)
                         chaplet-list--filters)))
    (if (assq :all filters)
        (chaplet-bd-list filters)
      (chaplet-bd-query (chaplet-bd--filters->expr filters)))))

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

(defun chaplet-list--entry (bead &optional indent)
  "Return a tabulated-list entry (ID . [ID TYPE STATE P STAGED TITLE]) for BEAD.
Cells are propertized with `chaplet-face' faces: ID → `chaplet-id',
State → pill face, P → priority dot+number, Type → type face, Staged → ✔.
When INDENT is non-nil, indent the title by two spaces."
  (let ((id (or (alist-get 'id bead) ""))
        (type (or (alist-get 'issue_type bead) ""))
        (status (or (alist-get 'status bead) ""))
        (priority (alist-get 'priority bead))
        (title (or (alist-get 'title bead) "")))
    (list id
          (vector
           (propertize id 'face 'chaplet-id)
           (propertize type 'face (chaplet-type-face type))
           (propertize status 'face (chaplet-state-face status))
           (chaplet-list--priority-dot priority)
           (if (chaplet-list--staged-p bead)
               (propertize "✔" 'face 'chaplet-staged)
             "")
           (if indent (concat "  " title) title)))))

(defun chaplet-list--group-by-epic (beads)
  "Return tabulated-list entries for BEADS, grouped by epic.
Epics appear as header rows; their child tasks (beads whose `parent'
matches the epic's id) appear indented below.  Beads without a parent
and that are not epics appear ungrouped at the end.  If an epic is
referenced by a child's parent but not present in BEADS, it is fetched
via `chaplet-bd-show' and inserted as a header."
  (let ((by-parent (make-hash-table :test 'equal))
        (epics-in-view (make-hash-table :test 'equal))
        (orphans nil)
        (entries nil))
    ;; Classify: index children by parent, collect epics in view.
    (dolist (b beads)
      (let ((parent (alist-get 'parent b))
            (type (alist-get 'issue_type b))
            (id (alist-get 'id b)))
        (cond
         ((string= type "epic")
          (puthash id t epics-in-view)
          ;; If no children reference it, it still gets a slot.
          (unless (gethash id by-parent)
            (puthash id nil by-parent)))
         (parent
          (puthash parent (cons b (gethash parent by-parent)) by-parent))
         (t
          (push b orphans)))))
    ;; For each parent referenced by children, ensure the epic header exists.
    ;; Emit groups: epic header + indented children.
    (maphash
     (lambda (epic-id children)
       (let ((epic-bead
              (or (cl-find epic-id beads
                           :key (lambda (b) (alist-get 'id b))
                           :test #'string=)
                  ;; Epic not in current view; fetch it for the header.
                  (chaplet-bd-show epic-id))))
         (when epic-bead
           (push (chaplet-list--entry epic-bead) entries))
         (dolist (child (nreverse children))
           (push (chaplet-list--entry child t) entries))))
     by-parent)
    ;; Ungrouped beads (no parent, not an epic) at the end.
    (dolist (b (nreverse orphans))
      (push (chaplet-list--entry b) entries))
    (nreverse entries)))

(defvar-local chaplet-list--modeline-string nil
  "Cached mode-line string for the current chaplet list buffer.
Computed once in `chaplet-list-refresh' (not per redisplay) so the
modeline pays no per-frame allocation cost.  `chaplet-list--modeline'
remains the pure recomputation helper.")

(defvar-local chaplet-list--beads nil
  "Most recently fetched bead data for this list buffer.
Used to avoid rebuilding an unchanged table on background refreshes.")

(defvar-local chaplet-list--has-rendered nil
  "Non-nil after this list buffer has rendered its first table.")

(defvar-local chaplet-list--rendered-view nil
  "View symbol represented by the most recent list rendering.")

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

(defconst chaplet-list--buffer-name "*chaplet*"
  "Name of the single list buffer (one buffer, no per-view stacking).")

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
  "Re-run the current view's query, rendering only changed data."
  (interactive)
  (let ((beads (chaplet-list--fetch chaplet-list--current-view)))
    (unless (and chaplet-list--has-rendered
                 (eq chaplet-list--current-view chaplet-list--rendered-view)
                 (equal beads chaplet-list--beads))
      (setq chaplet-list--beads beads)
      (setq chaplet-list--rendered-view chaplet-list--current-view)
      (setq tabulated-list-entries (chaplet-list--group-by-epic beads))
      (setq chaplet-list--modeline-string (chaplet-list--modeline))
      (setq mode-line-process chaplet-list--modeline-string)
      (tabulated-list-init-header)
      (tabulated-list-print)
      (setq chaplet-list--has-rendered t)))
  (chaplet--mark-fetch))

(defcustom chaplet-auto-refresh t
  "When non-nil, refresh visible Chaplet buffers after focus and on ticks.
A chaplet list, detail, or graph buffer re-fetches from `bd' when it is
shown in a window and at `chaplet-refresh-interval' while visible.  Write
actions from Chaplet always refresh every open view regardless of this
option."
  :type 'boolean
  :group 'chaplet)

(defcustom chaplet-refresh-delay 2
  "Minimum seconds between a fetch and a focus-triggered re-fetch.
`chaplet--refresh-on-focus' skips when the buffer's last fetch
(`chaplet--last-fetch') is newer than this many seconds, so an
explicit refresh (e.g. `chaplet-list-set-view') is not doubled by
the `window-buffer-change-functions' hook.  Buffers whose last fetch
is older (already stale) still refresh on focus."
  :type 'number
  :group 'chaplet)

(defcustom chaplet-refresh-interval 5
  "Seconds between background refreshes of visible Chaplet buffers.
Set to nil to disable tick refreshes while retaining focus refreshes."
  :type '(choice (const :tag "Disabled" nil) number)
  :group 'chaplet)

(defvar chaplet--refresh-timer nil
  "Timer which refreshes visible Chaplet buffers.")

(defvar-local chaplet--last-fetch nil
  "Wall-clock timestamp of the last bd fetch in this chaplet buffer.
Set by `chaplet--mark-fetch' on every fetch; consulted by refresh
scheduling to debounce focus refreshes and trigger periodic refreshes.")

(defun chaplet--mark-fetch ()
  "Record the current time as this buffer's last bd fetch."
  (setq chaplet--last-fetch (current-time)))

(defun chaplet--focus-stale-p ()
  "Return non-nil when this buffer needs a refresh: never fetched,
or last fetched more than `chaplet-refresh-delay' seconds ago."
  (or (null chaplet--last-fetch)
      (time-less-p (time-add chaplet--last-fetch chaplet-refresh-delay)
                   (current-time))))

(defun chaplet--refresh-buffer ()
  "Refresh the current Chaplet buffer without changing window selection."
  (cond
   ((derived-mode-p 'chaplet-list-mode) (chaplet-list-refresh))
   ((derived-mode-p 'chaplet-graph-mode) (chaplet-graph--refresh))
   ((and (boundp 'chaplet-detail-mode) chaplet-detail-mode
         (boundp 'chaplet-detail--id) chaplet-detail--id)
    (ignore-errors (chaplet-detail--populate chaplet-detail--id)))))

(defun chaplet--visible-buffers ()
  "Return distinct non-minibuffer buffers visible in any live frame."
  (delete-dups
   (cl-loop for frame in (frame-list)
            append (mapcar #'window-buffer (window-list frame nil)))))

(defun chaplet--ensure-refresh-timer ()
  "Start the periodic visible-buffer refresh timer when configured."
  (when (and chaplet-auto-refresh chaplet-refresh-interval
             (> chaplet-refresh-interval 0)
             (not (timerp chaplet--refresh-timer)))
    (setq chaplet--refresh-timer
          (run-at-time chaplet-refresh-interval chaplet-refresh-interval
                       #'chaplet--refresh-tick))))

(defun chaplet--refresh-tick ()
  "Refresh stale visible Chaplet buffers, then stop when none remain."
  (let ((buffers (chaplet--visible-buffers)))
    (if (null buffers)
        (when (timerp chaplet--refresh-timer)
          (cancel-timer chaplet--refresh-timer)
          (setq chaplet--refresh-timer nil))
      (dolist (buffer buffers)
        (with-current-buffer buffer
          (when (and chaplet-auto-refresh (chaplet--focus-stale-p))
            (condition-case err
                (chaplet--refresh-buffer)
              (error (message "chaplet: periodic refresh failed: %s"
                              (error-message-string err))))))))))

(defun chaplet-refresh-aux-buffers ()
  "Refresh every live chaplet detail and graph buffer.
The list is refreshed separately (see `chaplet-refresh-all'); this
handles the other views so a status change updates them in place."
  (dolist (b (buffer-list))
    (when (buffer-live-p b)
      (with-current-buffer b
        (cond
         ((and (boundp 'chaplet-detail-mode) chaplet-detail-mode
               (boundp 'chaplet-detail--id) chaplet-detail--id)
          (ignore-errors (chaplet-detail--populate chaplet-detail--id)))
         ((derived-mode-p 'chaplet-graph-mode)
          (ignore-errors (chaplet-graph--refresh))))))))

(defun chaplet-refresh-all ()
  "Refresh every live chaplet buffer (list, detail, graph).
Called after write actions so all open views reflect the new state
automatically, without a manual `g'."
  (interactive)
  (let ((lb (get-buffer chaplet-list--buffer-name)))
    (if (buffer-live-p lb)
        (with-current-buffer lb
          (when (derived-mode-p 'chaplet-list-mode)
            (chaplet-list-refresh)))
      (when (derived-mode-p 'chaplet-list-mode)
        (chaplet-list-refresh))))
  (chaplet-refresh-aux-buffers))

(defun chaplet--refresh-on-focus (_window)
  "Auto-refresh this Chaplet buffer when it becomes visible in a window.
Installed buffer-locally on `window-buffer-change-functions'.  Focus refresh
is gated by `chaplet-auto-refresh' and debounced by
`chaplet-refresh-delay'; visible buffers also receive periodic ticks."
  (when chaplet-auto-refresh
    (chaplet--ensure-refresh-timer)
    (when (and (buffer-live-p (current-buffer)) (chaplet--focus-stale-p))
      (chaplet--refresh-buffer))))

(defun chaplet-list-open (id)
  "Open bead ID via `chaplet-detail' when present; else raw `bd show'."
  (interactive (list (tabulated-list-get-id)))
  (if (fboundp 'chaplet-detail)
      (chaplet-detail id)
    (chaplet-list--show-raw id)))

(defun chaplet-list-set-view (name)
  "Switch the bead browser to view NAME (a symbol).
Prepares the shared `*chaplet*' buffer (running `chaplet-list-mode'
when fresh — its init fetches the view) before showing it, so the
`chaplet--refresh-on-focus' hook that fires on display sees a fresh
`chaplet--last-fetch' and skips: exactly one bd fetch per call."
  (interactive
   (list (intern
          (completing-read "View: "
                           (mapcar #'symbol-name (chaplet-bd--view-names))
                           nil t))))
  (let ((buf (get-buffer-create chaplet-list--buffer-name)))
    (with-current-buffer buf
      (setq chaplet-list--current-view name)
      (if (eq major-mode 'chaplet-list-mode)
          (chaplet-list-refresh)
        (chaplet-list-mode)))
    (switch-to-buffer buf)))

(defun chaplet-list-graph ()
  "Open the graph for the current list view (`s')."
  (interactive)
  (chaplet-graph chaplet-list--current-view))

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
  (when (boundp 'window-buffer-change-functions)
    (add-hook 'window-buffer-change-functions #'chaplet--refresh-on-focus nil t))
  (hl-line-mode 1)
  (setq mode-line-process chaplet-list--modeline-string)
  (face-remap-add-relative 'header-line '(chaplet-header header-line))
  (setq-local chaplet-bar--map chaplet-list-mode-map)
  (setq-local chaplet-bar--specs chaplet-list--bar-specs)
  (setq-local chaplet-bar--extra nil)
  (chaplet-bar--install)
  (chaplet-list-refresh))

(defun chaplet-list--bind (key cmd)
  "Bind KEY to CMD in `chaplet-list-mode-map', evil-aware.
Mirrors `chaplet-graph--bind': also binds in evil normal and motion
states so the list keys work when evil is active instead of leaking
to evil bindings (e.g. `?' → evil-search-backward, which lives in the
motion state).  Uses the evil-define-key* *function* (not the
evil-define-key macro) so this file byte-compiles safely when evil
isn't loaded.  `fboundp' is true for macros, which would otherwise
compile to a function call and signal `invalid-function' at runtime."
  (define-key chaplet-list-mode-map key cmd)
  (when (and (featurep 'evil) (fboundp 'evil-define-key*))
    (evil-define-key* 'normal chaplet-list-mode-map key cmd)
    (evil-define-key* 'motion chaplet-list-mode-map key cmd)))

(chaplet-list--bind (kbd "RET") #'chaplet-list-open)
(chaplet-list--bind (kbd "v") #'chaplet-list-set-view)
(chaplet-list--bind (kbd "s") #'chaplet-list-graph)
(chaplet-list--bind (kbd "q") #'quit-window)
(define-key chaplet-list-mode-map [mouse-1] #'chaplet-list-open)

;;;###autoload
(defun chaplet-list ()
  "Open the chaplet bead browser on the inbox (staged) view."
  (interactive)
  (chaplet-list-set-view 'inbox))

(provide 'chaplet-list)
;;; chaplet-list.el ends here
