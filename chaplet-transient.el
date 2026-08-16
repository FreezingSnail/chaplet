;;; chaplet-transient.el --- magit-style action menus per bead state -*- lexical-binding: t; -*-

;; Transient (magit-style) dispatch popup over the bead at point.  The menu
;; is tailored to the bead's state: staged (deferred) rows get approve/reject,
;; open rows get comment/edit/new, everything else is comment-only.  Write
;; actions refresh the list afterwards.  `?' in `chaplet-list-mode' opens it.

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

(defun chaplet-transient--actions-for-state (state)
  "Return the list of action symbols allowed for bead STATE (status string).
Staged (deferred) rows: approve/reject/comment/edit-design.
Open rows: comment/edit-design/new.  Everything else: comment only."
  (pcase state
    ("deferred" '(approve reject comment edit-design))
    ("open"     '(comment edit-design new))
    (_          '(comment))))

(defun chaplet-transient--action-visible-p (action)
  "Return non-nil when ACTION is allowed for `chaplet-transient--state'."
  (memq action (chaplet-transient--actions-for-state chaplet-transient--state)))

;;; Context captured when the menu opens

(defvar chaplet-transient--id nil
  "Bead id at point when the transient was invoked.")

(defvar chaplet-transient--state nil
  "Status string of the bead at point when the transient was invoked.")

(defvar chaplet-transient--list-buffer nil
  "The `chaplet-list-mode' buffer the transient was opened from.")

(defun chaplet-transient--refresh ()
  "Refresh the originating list buffer, else the current buffer."
  (if (buffer-live-p chaplet-transient--list-buffer)
      (with-current-buffer chaplet-transient--list-buffer
        (chaplet-list-refresh))
    (chaplet-list-refresh)))

;;; Actions

(defun chaplet-approve (&optional id)
  "Approve (undefer) the bead at point, then refresh the list."
  (interactive)
  (let ((id (or id (chaplet-transient--id-at-point))))
    (when id
      (chaplet-bd-undefer id)
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

(defun chaplet-new ()
  "Create a new bead from prompts, then refresh the list."
  (interactive)
  (let* ((title (read-string "Title: "))
         (type (read-string "Type (task/bug/feature/epic): "))
         (desc (read-string "Description: ")))
    (chaplet-bd-create title type desc)
    (chaplet-transient--refresh)))

(defun chaplet-refresh ()
  "Refresh the chaplet list."
  (interactive)
  (chaplet-list-refresh))

;;; Detail-buffer delegation (id-taking, no list refresh)

(defun chaplet-transient-approve (id)
  "Approve (undefer) bead ID.  Used by `chaplet-detail-approve'."
  (interactive "sBead id: ")
  (chaplet-bd-undefer id))

(defun chaplet-transient-reject (id)
  "Reject bead ID: prompt for feedback and comment \"rejected: <fb>\"."
  (interactive "sBead id: ")
  (let ((fb (read-string "Reject feedback: ")))
    (chaplet-bd-comment id (format "rejected: %s" fb))))

(defun chaplet-transient-comment (id)
  "Comment on bead ID.  Used by `chaplet-detail-comment'."
  (interactive "sBead id: ")
  (let ((text (read-string "Comment: ")))
    (chaplet-bd-comment id text)))

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
  ["Bead"
   ("a" "approve" chaplet-approve
    :if (lambda () (chaplet-transient--action-visible-p 'approve)))
   ("r" "reject" chaplet-reject
    :if (lambda () (chaplet-transient--action-visible-p 'reject)))
   ("c" "comment" chaplet-comment
    :if (lambda () (chaplet-transient--action-visible-p 'comment)))
   ("e" "edit design" chaplet-edit-design
    :if (lambda () (chaplet-transient--action-visible-p 'edit-design)))
   ("n" "new bead" chaplet-new
    :if (lambda () (chaplet-transient--action-visible-p 'new)))]
  ["General"
   ("g" "refresh" chaplet-refresh)
   ("v" "switch view" chaplet-list-set-view)
   ("s" "graph" chaplet-list-graph
    :if (lambda () (fboundp 'chaplet-list-graph)))]
  (interactive)
  (setq chaplet-transient--id (chaplet-transient--id-at-point))
  (setq chaplet-transient--state (chaplet-transient--state-at-point))
  (setq chaplet-transient--list-buffer (current-buffer))
  (transient-setup 'chaplet-transient))

;;; Key binding (evil-aware via the helper: no duplicate, single source)

(chaplet-list--bind (kbd "?") #'chaplet-transient)

(provide 'chaplet-transient)
;;; chaplet-transient.el ends here
