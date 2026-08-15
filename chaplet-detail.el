;;; chaplet-detail.el --- read-only markdown detail buffer for a bead -*- lexical-binding: t; -*-

;; Rich read-only detail view of a single bead, rendered as markdown.
;; Uses `markdown-mode' when available; otherwise degrades to
;; fundamental-mode + font-lock (no hard dependency on markdown-mode).

(require 'chaplet-bd)

(defvar-local chaplet-detail--id nil
  "Bead id shown by the current detail buffer.")

;;; Rendering (pure)

(defun chaplet-detail--render-header (bead)
  "Render the markdown header for BEAD (an alist)."
  (let* ((id (or (alist-get 'id bead) ""))
         (title (or (alist-get 'title bead) id))
         (status (or (alist-get 'status bead) ""))
         (priority (alist-get 'priority bead))
         (type (or (alist-get 'issue_type bead) ""))
         (owner (or (alist-get 'owner bead) ""))
         (created (or (alist-get 'created_at bead) ""))
         (labels (alist-get 'labels bead)))
    (concat "# " title "\n\n"
            (format "*id:* %s · *status:* %s · *priority:* %s · *type:* %s · *owner:* %s · *created:* %s\n"
                    id status (or priority "") type owner created)
            (when labels
              (format "*labels:* %s\n" (mapconcat #'identity labels ", "))))))

(defun chaplet-detail--section (title body)
  "Render a \"## TITLE\" markdown section when BODY is non-empty.
Return nil (empty string) when BODY is nil or blank."
  (when (and body (not (string-empty-p (string-trim body))))
    (format "\n## %s\n\n%s\n" title body)))

(defun chaplet-detail--render-comments (comments)
  "Render COMMENTS as a markdown section; each comment is author + text."
  (when comments
    (concat "\n## Comments\n\n"
            (mapconcat (lambda (c)
                         (format "- **%s** — %s"
                                 (or (alist-get 'author c) "unknown")
                                 (or (alist-get 'text c) (alist-get 'body c) "")))
                       comments
                       "\n")
            "\n")))

(defun chaplet-detail--render (bead)
  "Render BEAD (a bead alist) as a markdown string.
Sections Description/Design/Acceptance/Comments are omitted when empty."
  (concat
   (chaplet-detail--render-header bead)
   (chaplet-detail--section "Description" (alist-get 'description bead))
   (chaplet-detail--section "Design" (alist-get 'design bead))
   (chaplet-detail--section "Acceptance" (alist-get 'acceptance bead))
   (chaplet-detail--render-comments (alist-get 'comments bead))))

;;; Buffer + mode

(defun chaplet-detail--activate-major-mode ()
  "Enable `markdown-mode' when available; else fundamental + font-lock.
Return the active major mode symbol."
  (if (require 'markdown-mode nil t)
      (progn (markdown-mode) 'markdown-mode)
    (progn (fundamental-mode) (font-lock-mode 1) 'fundamental-mode)))

(defun chaplet-detail--populate (id)
  "Fetch bead ID and render it into the current buffer."
  (let ((bead (chaplet-bd-show id)))
    (unless bead
      (error "chaplet: no bead %s" id))
    (let ((inhibit-read-only t))
      (erase-buffer)
      (insert (chaplet-detail--render
               (cons (cons 'comments (chaplet-bd-comments id)) bead)))
      (goto-char (point-min)))))

(defun chaplet-detail-quit ()
  "Quit the detail buffer, returning to the previous buffer."
  (interactive)
  (quit-window))

(defun chaplet-detail-refresh ()
  "Re-fetch and re-render the current bead."
  (interactive)
  (when chaplet-detail--id
    (chaplet-detail--populate chaplet-detail--id)))

(defun chaplet-detail-comment ()
  "Comment on the current bead (delegates to chaplet-transient when built)."
  (interactive)
  (if (fboundp 'chaplet-transient-comment)
      (chaplet-transient-comment chaplet-detail--id)
    (message "chaplet: comment action not yet wired (chaplet-transient)")))

(defun chaplet-detail-approve ()
  "Approve the current bead (delegates to chaplet-transient when built)."
  (interactive)
  (if (fboundp 'chaplet-transient-approve)
      (chaplet-transient-approve chaplet-detail--id)
    (message "chaplet: approve action not yet wired (chaplet-transient)")))

(defun chaplet-detail-reject ()
  "Reject the current bead (delegates to chaplet-transient when built)."
  (interactive)
  (if (fboundp 'chaplet-transient-reject)
      (chaplet-transient-reject chaplet-detail--id)
    (message "chaplet: reject action not yet wired (chaplet-transient)")))

(defvar chaplet-detail-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "q") #'chaplet-detail-quit)
    (define-key map (kbd "g") #'chaplet-detail-refresh)
    (define-key map (kbd "c") #'chaplet-detail-comment)
    (define-key map (kbd "a") #'chaplet-detail-approve)
    (define-key map (kbd "r") #'chaplet-detail-reject)
    map)
  "Keymap for `chaplet-detail-mode'.")

;;;###autoload
(define-minor-mode chaplet-detail-mode
  "Minor mode for chaplet bead detail buffers.
\\{chaplet-detail-mode-map}"
  :lighter " chaplet"
  :keymap chaplet-detail-mode-map)

;;;###autoload
(defun chaplet-detail (id)
  "Show bead ID in a read-only markdown detail buffer."
  (interactive "sBead id: ")
  (let ((buf (get-buffer-create (format "*chaplet:detail:%s*" id))))
    (with-current-buffer buf
      (chaplet-detail--activate-major-mode)
      (chaplet-detail-mode 1)
      (setq-local chaplet-detail--id id)
      (chaplet-detail--populate id)
      (read-only-mode 1))
    (pop-to-buffer buf)))

(provide 'chaplet-detail)
;;; chaplet-detail.el ends here
