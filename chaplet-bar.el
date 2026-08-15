;;; chaplet-bar.el --- keybinding reference bar for chaplet buffers -*- lexical-binding: t; -*-

;; Persistent bottom bar (mode-line footer) in the chaplet list and graph
;; buffers.  Lists the buffer's available keybindings as a quick reference.
;; Entries are derived from each buffer's keymap via `lookup-key'; keys that
;; are not bound are omitted, so the bar always reflects the real bindings.
;; Idempotent: the bar is a single `(:eval ...)' element appended to the
;; buffer-local `mode-line-format' once; re-renders never duplicate it.
;; Zero external deps (built-in `kbd' / `lookup-key' only).

(require 'chaplet-face)

(defvar-local chaplet-bar--map nil
  "Keymap the bar derives its entries from (buffer-local).")

(defvar-local chaplet-bar--specs nil
  "Candidate entries for the bar: alist (KEY-STRING . LABEL).
KEY-STRING is parsed with `kbd'.  Entries whose key is not bound in
`chaplet-bar--map' are omitted from the bar.")

(defvar-local chaplet-bar--extra nil
  "Entries always shown: alist (KEY-STRING . LABEL).
Used for bindings that are not plain keys in `chaplet-bar--map'
(e.g. per-node mouse hot-spots in the graph buffer).")

(defvar-local chaplet-bar--installed nil
  "Non-nil when the bar element has been appended to `mode-line-format'.")

(defun chaplet-bar--bound ()
  "Return entries from `chaplet-bar--specs' whose keys are bound in the map.
Each entry is (KEY-STRING . LABEL) as in `chaplet-bar--specs'."
  (delq nil
        (mapcar (lambda (spec)
                  (when (and chaplet-bar--map
                             (lookup-key chaplet-bar--map (kbd (car spec))))
                    spec))
                chaplet-bar--specs)))

(defun chaplet-bar--entries ()
  "Return the entries to display: bound specs followed by extras."
  (append (chaplet-bar--bound) chaplet-bar--extra))

(defun chaplet-bar--render ()
  "Return the mode-line bar string for the current buffer.
Renders each entry as \"[KEY] LABEL\" with face `chaplet-bar'; \"\"
when there are no entries."
  (let ((entries (chaplet-bar--entries)))
    (if (null entries)
        ""
      (concat " "
              (mapconcat
               (lambda (e)
                 (propertize (format "[%s] %s" (car e) (cdr e))
                             'face 'chaplet-bar))
               entries
               " ")))))

(defun chaplet-bar--install ()
  "Append the keybinding bar to the buffer-local `mode-line-format'.
Idempotent: the `(:eval (chaplet-bar--render))' element is appended at
most once per buffer."
  (unless chaplet-bar--installed
    (setq-local chaplet-bar--installed t)
    (when (consp mode-line-format)
      (setq-local mode-line-format
                  (append mode-line-format '((:eval (chaplet-bar--render))))))))

(provide 'chaplet-bar)
;;; chaplet-bar.el ends here
