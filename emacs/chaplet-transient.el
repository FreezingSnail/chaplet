;;; chaplet-transient.el --- magit-style action menus per bead state -*- lexical-binding: t; -*-

;; Transient (magit-style) dispatch popup over the bead at point.  The menu
;; is tailored to deferred rows: every deferred bead gets one approve action;
;; staged rows additionally get reject.  Write actions refresh the list afterwards.
;; `?' in `chaplet-list-mode' opens it.

(require 'chaplet-bd)
(require 'chaplet-list)
(require 'transient)

;;; Bead at point

(defun chaplet-transient--id-at-point ()
  "Return the bead id at point in a `chaplet-list-mode' buffer, or nil."
  (when (derived-mode-p 'chaplet-list-mode)
    (tabulated-list-get-id)))

(defun chaplet-transient--state-at-point ()
  "Return the status string of the bead at point, or nil."
  (let ((id (chaplet-transient--id-at-point)))
    (when id
      (alist-get 'status (chaplet-bd-show id)))))

;;; State -> visible actions (pure)

(defun chaplet-transient--staged-p-at-point ()
  "Return non-nil when the bead at point is a staged deferred bead."
  (let ((id (chaplet-transient--id-at-point)))
    (when id
      (chaplet-list--staged-p (chaplet-bd-show id)))))

(defun chaplet-transient--actions-for-state (state &optional staged-p human-p)
  "Return action symbols allowed for STATE, STAGED-P, and HUMAN-P.
Every bead supports metadata and dependency controls.  Open lifecycle states
can be claimed, deferred, closed, duplicated, or superseded; closed beads can
be reopened.  Staged and human-specific actions remain state-aware."
  (append '(comment edit-design edit-field new assign priority label-add
                    label-remove dependency-add dependency-remove refresh view)
          (if (string= state "closed")
              '(reopen)
            '(claim defer close duplicate supersede))
          (pcase state
            ("deferred" (append '(approve) (and staged-p '(reject))))
            (_ nil))
          (and human-p '(human-respond human-dismiss))))

(defun chaplet-transient--action-visible-p (action)
  "Return non-nil when ACTION is allowed by captured bead context."
  (memq action
        (chaplet-transient--actions-for-state chaplet-transient--state
                                               chaplet-transient--staged-p
                                               chaplet-transient--human-p)))

;;; Context captured when the menu opens

(defvar chaplet-transient--id nil
  "Bead id at point when the transient was invoked.")

(defvar chaplet-transient--state nil
  "Status string of the bead at point when the transient was invoked.")

(defvar chaplet-transient--staged-p nil
  "Whether the bead was staged when the transient was invoked.")

(defvar chaplet-transient--human-p nil
  "Whether the bead had the `human' label when the transient was invoked.")

(defvar chaplet-transient--list-buffer nil
  "The `chaplet-list-mode' buffer the transient was opened from.")

(defun chaplet-transient--refresh ()
  "Refresh all live chaplet buffers after a write action.
See `chaplet-refresh-all'."
  (chaplet-refresh-all))

;;; Actions

(defun chaplet-undefer (&optional id)
  "Undefer a plain deferred bead at point, then refresh."
  (interactive)
  (let ((id (or id (chaplet-transient--id-at-point))))
    (when id
      (chaplet-bd-undefer id)
      (chaplet-transient--refresh))))

(defun chaplet-approve (&optional id)
  "Move deferred bead at point to open and clear any staged label, refresh."
  (interactive)
  (let ((id (or id (chaplet-transient--id-at-point))))
    (when id
      (chaplet-bd-undefer id)
      (chaplet-bd-label-remove id chaplet-staged-label)
      (chaplet-transient--refresh))))

(defun chaplet-reject (&optional id)
  "Reject the bead at point: prompt for feedback, comment, refresh.
Rejection stays staged (a comment is added, the bead is not undeferred)."
  (interactive)
  (let* ((id (or id (chaplet-transient--id-at-point)))
         (fb (read-string "Reject feedback: ")))
    (when id
      (chaplet-bd-comment id (format "rejected: %s" fb))
      (chaplet-transient--refresh))))

(defun chaplet-comment (&optional id)
  "Comment on the bead at point, then refresh the list."
  (interactive)
  (let* ((id (or id (chaplet-transient--id-at-point)))
         (text (read-string "Comment: ")))
    (when id
      (chaplet-bd-comment id text)
      (chaplet-transient--refresh))))

(defun chaplet-edit-design (&optional id)
  "Edit the design notes of the bead at point, then refresh the list."
  (interactive)
  (let* ((id (or id (chaplet-transient--id-at-point)))
         (design (read-string "Design: ")))
    (when id
      (chaplet-bd-update-design id design)
      (chaplet-transient--refresh))))

(defun chaplet-edit-field (&optional id)
  "Edit one core field of bead ID, preserving its current value as default."
  (interactive)
  (let* ((id (or id (chaplet-transient--id-at-point)))
         (field (intern (completing-read "Field: "
                                        '("title" "description" "type"
                                          "design" "acceptance") nil t)))
         (bead (and id (chaplet-bd-show id)))
         (value (read-string (format "%s: " field)
                             (or (alist-get field bead) ""))))
    (when id
      (chaplet-bd-update id field value)
      (chaplet-transient--refresh))))

(defun chaplet-claim (&optional id)
  "Claim bead ID for the current bd actor, then refresh."
  (interactive)
  (when-let ((id (or id (chaplet-transient--id-at-point))))
    (chaplet-bd-claim id)
    (chaplet-transient--refresh)))

(defun chaplet-assign (&optional id)
  "Assign bead ID; a blank assignee unassigns it."
  (interactive)
  (when-let ((id (or id (chaplet-transient--id-at-point))))
    (chaplet-bd-assign id (read-string "Assignee (blank = unassign): "))
    (chaplet-transient--refresh)))

(defun chaplet-set-priority (&optional id)
  "Set bead ID priority (0–4), then refresh."
  (interactive)
  (when-let ((id (or id (chaplet-transient--id-at-point))))
    (let ((priority (read-string "Priority (0-4): ")))
      (unless (member priority '("0" "1" "2" "3" "4"))
        (user-error "chaplet: priority must be 0–4"))
      (chaplet-bd-priority id priority)
      (chaplet-transient--refresh))))

(defun chaplet-add-label (&optional id)
  "Add a label to bead ID, then refresh."
  (interactive)
  (when-let ((id (or id (chaplet-transient--id-at-point))))
    (chaplet-bd-label id (read-string "Add label: "))
    (chaplet-transient--refresh)))

(defun chaplet-remove-label (&optional id)
  "Remove a label from bead ID, then refresh."
  (interactive)
  (when-let ((id (or id (chaplet-transient--id-at-point))))
    (chaplet-bd-label-remove id (read-string "Remove label: "))
    (chaplet-transient--refresh)))

(defun chaplet-add-dependency (&optional id)
  "Make bead ID depend on a prompted bead, then refresh."
  (interactive)
  (when-let ((id (or id (chaplet-transient--id-at-point))))
    (chaplet-bd-dependency-add id (read-string "Depends on: "))
    (chaplet-transient--refresh)))

(defun chaplet-remove-dependency (&optional id)
  "Remove a prompted dependency from bead ID, then refresh."
  (interactive)
  (when-let ((id (or id (chaplet-transient--id-at-point))))
    (chaplet-bd-dependency-remove id (read-string "Remove dependency: "))
    (chaplet-transient--refresh)))

(defun chaplet-defer (&optional id)
  "Defer bead ID, then refresh."
  (interactive)
  (when-let ((id (or id (chaplet-transient--id-at-point))))
    (chaplet-bd-defer id)
    (chaplet-transient--refresh)))

(defun chaplet-close (&optional id)
  "Close bead ID after optional reason, then refresh."
  (interactive)
  (when-let ((id (or id (chaplet-transient--id-at-point))))
    (chaplet-bd-close id (read-string "Close reason (optional): "))
    (chaplet-transient--refresh)))

(defun chaplet-reopen (&optional id)
  "Reopen bead ID after optional reason, then refresh."
  (interactive)
  (when-let ((id (or id (chaplet-transient--id-at-point))))
    (chaplet-bd-reopen id (read-string "Reopen reason (optional): "))
    (chaplet-transient--refresh)))

(defun chaplet-duplicate (&optional id)
  "Close bead ID as duplicate of a prompted canonical bead."
  (interactive)
  (when-let ((id (or id (chaplet-transient--id-at-point))))
    (let ((canonical (read-string "Canonical bead: ")))
      (when (y-or-n-p (format "Mark %s duplicate of %s? " id canonical))
        (chaplet-bd-duplicate id canonical)
        (chaplet-transient--refresh)))))

(defun chaplet-supersede (&optional id)
  "Close bead ID as superseded by a prompted replacement bead."
  (interactive)
  (when-let ((id (or id (chaplet-transient--id-at-point))))
    (let ((replacement (read-string "Replacement bead: ")))
      (when (y-or-n-p (format "Mark %s superseded by %s? " id replacement))
        (chaplet-bd-supersede id replacement)
        (chaplet-transient--refresh)))))

(defun chaplet-human-respond (&optional id)
  "Respond to human bead ID and close it."
  (interactive)
  (when-let ((id (or id (chaplet-transient--id-at-point))))
    (chaplet-bd-human-respond id (read-string "Response: "))
    (chaplet-transient--refresh)))

(defun chaplet-human-dismiss (&optional id)
  "Dismiss human bead ID, then refresh."
  (interactive)
  (when-let ((id (or id (chaplet-transient--id-at-point))))
    (chaplet-bd-human-dismiss id (read-string "Dismiss reason (optional): "))
    (chaplet-transient--refresh)))

(defun chaplet-new ()
  "Create a new bead from prompts, then refresh the list."
  (interactive)
  (let* ((title (read-string "Title: "))
         (type (read-string "Type (task/bug/feature/epic): "))
         (desc (read-string "Description: ")))
    (chaplet-bd-create title type desc)
    (chaplet-transient--refresh)))

(defun chaplet-refresh ()
  "Refresh every live chaplet buffer (list, detail, graph)."
  (interactive)
  (chaplet-refresh-all))

;;; Detail-buffer delegation (id-taking, no list refresh)

(defun chaplet-transient-approve (id)
  "Approve (undefer) bead ID and strip its staged label.
Used by `chaplet-detail-approve'.  Refreshes all chaplet buffers so the
list and detail pick up the status change."
  (interactive "sBead id: ")
  (chaplet-bd-undefer id)
  (chaplet-bd-label-remove id chaplet-staged-label)
  (chaplet-refresh-all))

(defun chaplet-transient-reject (id)
  "Reject bead ID: prompt for feedback and comment \"rejected: <fb>\".
Refreshes all chaplet buffers afterwards."
  (interactive "sBead id: ")
  (let ((fb (read-string "Reject feedback: ")))
    (chaplet-bd-comment id (format "rejected: %s" fb)))
  (chaplet-refresh-all))

(defun chaplet-transient-comment (id)
  "Comment on bead ID.  Used by `chaplet-detail-comment'.
Refreshes all chaplet buffers afterwards."
  (interactive "sBead id: ")
  (let ((text (read-string "Comment: ")))
    (chaplet-bd-comment id text))
  (chaplet-refresh-all))

;;; Prefix

(defun chaplet-transient--description ()
  "Return the header string for the transient popup."
  (if chaplet-transient--id
      (format "Bead %s (%s)"
              chaplet-transient--id (or chaplet-transient--state "?"))
    "Chaplet actions"))

(transient-define-prefix chaplet-transient ()
  "Actions for the bead at point."
  [:description chaplet-transient--description]
  ["Lifecycle"
   ("a" "approve" chaplet-approve
    :if (lambda () (chaplet-transient--action-visible-p 'approve)))
   ("r" "reject" chaplet-reject
    :if (lambda () (chaplet-transient--action-visible-p 'reject)))
   ("C" "claim" chaplet-claim
    :if (lambda () (chaplet-transient--action-visible-p 'claim)))
   ("A" "assign" chaplet-assign
    :if (lambda () (chaplet-transient--action-visible-p 'assign)))
   ("x" "close" chaplet-close
    :if (lambda () (chaplet-transient--action-visible-p 'close)))
   ("o" "reopen" chaplet-reopen
    :if (lambda () (chaplet-transient--action-visible-p 'reopen)))
   ("=" "duplicate" chaplet-duplicate
    :if (lambda () (chaplet-transient--action-visible-p 'duplicate)))
   ("S" "supersede" chaplet-supersede
    :if (lambda () (chaplet-transient--action-visible-p 'supersede)))]
  ["Edit"
   ("c" "comment" chaplet-comment
    :if (lambda () (chaplet-transient--action-visible-p 'comment)))
   ("e" "edit design" chaplet-edit-design
    :if (lambda () (chaplet-transient--action-visible-p 'edit-design)))
   ("E" "edit field" chaplet-edit-field
    :if (lambda () (chaplet-transient--action-visible-p 'edit-field)))
   ("p" "priority" chaplet-set-priority
    :if (lambda () (chaplet-transient--action-visible-p 'priority)))
   ("l" "add label" chaplet-add-label
    :if (lambda () (chaplet-transient--action-visible-p 'label-add)))
   ("L" "remove label" chaplet-remove-label
    :if (lambda () (chaplet-transient--action-visible-p 'label-remove)))
   ("d" "add dependency" chaplet-add-dependency
    :if (lambda () (chaplet-transient--action-visible-p 'dependency-add)))
   ("D" "remove dependency" chaplet-remove-dependency
    :if (lambda () (chaplet-transient--action-visible-p 'dependency-remove)))
   ("f" "defer" chaplet-defer
    :if (lambda () (chaplet-transient--action-visible-p 'defer)))
   ("n" "new bead" chaplet-new
    :if (lambda () (chaplet-transient--action-visible-p 'new)))]
  ["Human"
   ("h" "respond + close" chaplet-human-respond
    :if (lambda () (chaplet-transient--action-visible-p 'human-respond)))
   ("H" "dismiss" chaplet-human-dismiss
    :if (lambda () (chaplet-transient--action-visible-p 'human-dismiss)))]
  ["General"
   ("g" "refresh" chaplet-refresh)
   ("v" "switch view" chaplet-list-set-view)
   ("s" "graph" chaplet-list-graph
    :if (lambda () (fboundp 'chaplet-list-graph)))]
  (interactive)
  (setq chaplet-transient--id (chaplet-transient--id-at-point))
  (let ((bead (and chaplet-transient--id
                   (chaplet-bd-show chaplet-transient--id))))
    (setq chaplet-transient--state (alist-get 'status bead))
    (setq chaplet-transient--staged-p (chaplet-list--staged-p bead))
    (setq chaplet-transient--human-p
          (member chaplet-human-label (alist-get 'labels bead))))
  (setq chaplet-transient--list-buffer (current-buffer))
  (transient-setup 'chaplet-transient))

;;; Key binding (evil-aware via the helper: no duplicate, single source)

(chaplet-list--bind (kbd "?") #'chaplet-transient)

(provide 'chaplet-transient)
;;; chaplet-transient.el ends here
