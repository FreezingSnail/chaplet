;;; chaplet.el --- entry point + global minor-mode + keymap -*- lexical-binding: t; -*-

;; Single entry point for the chaplet bead browser.  Requires every module,
;; exposes `M-x chaplet' (open the staged inbox), a global minor mode
;; `chaplet-mode', and its keymap (`C-c b b' → chaplet, `C-c b s' → graph).

(require 'chaplet-bd)
(require 'chaplet-list)
(require 'chaplet-transient)
(require 'chaplet-detail)
(require 'chaplet-graph)

;;;###autoload
(defun chaplet ()
  "Open the chaplet bead browser on the inbox (staged) view."
  (interactive)
  (chaplet-list-set-view 'inbox))

(defvar chaplet-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c b b") #'chaplet)
    (define-key map (kbd "C-c b s") #'chaplet-graph)
    map)
  "Keymap for `chaplet-mode'.")

;;;###autoload
(define-minor-mode chaplet-mode
  "Global minor mode for the chaplet bead browser."
  :global t
  :keymap chaplet-mode-map)

(provide 'chaplet)
;;; chaplet.el ends here
