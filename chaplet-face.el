;;; chaplet-face.el --- theme-adaptive faces + SVG colors -*- lexical-binding: t; -*-

;; Single source of truth for chaplet faces: state pills, priority dots,
;; type faces, list chrome.  Detects dark vs light themes from the
;; `default' face background, applies the matching palette via
;; `face-spec-set', and re-applies on `after-load-theme-hook'.  SVG graph
;; fills are derived from the same faces via `face-attribute' — one palette
;; for text and graph rendering.  Safe in batch (no display required).

(require 'color)

(defgroup chaplet nil
  "Magit-style bead browser over the `bd' CLI."
  :group 'tools)

;;; Faces

;; State faces (defface defaults = dark palette; adapted at runtime).

(defface chaplet-state-deferred
  '((t :foreground "#d19a66" :background "#3d2e1a" :box t))
  "Face for deferred (staged) beads."
  :group 'chaplet)

(defface chaplet-state-in-progress
  '((t :foreground "#61afef" :background "#1f3b5c" :box t))
  "Face for in-progress beads."
  :group 'chaplet)

(defface chaplet-state-blocked
  '((t :foreground "#e06c75" :background "#4a2226" :box t))
  "Face for blocked beads."
  :group 'chaplet)

(defface chaplet-state-closed
  '((t :foreground "#5c6370" :background "#2b2f36" :box t))
  "Face for closed beads."
  :group 'chaplet)

(defface chaplet-state-open
  '((t :foreground "#98c379" :background "#1e3a25" :box t))
  "Face for open beads."
  :group 'chaplet)

;; Priority dot faces.

(defface chaplet-priority-high
  '((t :foreground "#e06c75"))
  "Face for high-priority beads."
  :group 'chaplet)

(defface chaplet-priority-medium
  '((t :foreground "#d19a66"))
  "Face for medium-priority beads."
  :group 'chaplet)

(defface chaplet-priority-low
  '((t :foreground "#98c379"))
  "Face for low-priority beads."
  :group 'chaplet)

;; Type faces.

(defface chaplet-type-epic
  '((t :foreground "#c678dd"))
  "Face for epic-type beads."
  :group 'chaplet)

(defface chaplet-type-task
  '((t :foreground "#61afef"))
  "Face for task-type beads."
  :group 'chaplet)

(defface chaplet-type-bug
  '((t :foreground "#e06c75"))
  "Face for bug-type beads."
  :group 'chaplet)

;; List chrome.

(defface chaplet-header
  '((t :inherit tabulated-list-header :weight bold))
  "Face for the list header row."
  :group 'chaplet)

(defface chaplet-staged
  '((t :foreground "#98c379"))
  "Face for the staged marker in the list."
  :group 'chaplet)

(defface chaplet-id
  '((t :inherit fixed-pitch))
  "Face for bead ids."
  :group 'chaplet)

;;; Palettes

(defconst chaplet-face--dark-palette
  '((chaplet-state-deferred     . "#d19a66")
    (chaplet-state-in-progress  . "#61afef")
    (chaplet-state-blocked      . "#e06c75")
    (chaplet-state-closed       . "#5c6370")
    (chaplet-state-open         . "#98c379")
    (chaplet-priority-high      . "#e06c75")
    (chaplet-priority-medium    . "#d19a66")
    (chaplet-priority-low       . "#98c379")
    (chaplet-type-epic          . "#c678dd")
    (chaplet-type-task          . "#61afef")
    (chaplet-type-bug           . "#e06c75")
    (chaplet-staged             . "#98c379"))
  "Dark-theme palette: alist of (face . foreground color).")

(defconst chaplet-face--light-palette
  '((chaplet-state-deferred     . "#8a5a12")
    (chaplet-state-in-progress  . "#1f6fb2")
    (chaplet-state-blocked      . "#b3261e")
    (chaplet-state-closed       . "#6e7278")
    (chaplet-state-open         . "#1f7a3d")
    (chaplet-priority-high      . "#b3261e")
    (chaplet-priority-medium    . "#8a5a12")
    (chaplet-priority-low       . "#1f7a3d")
    (chaplet-type-epic          . "#7b2d8b")
    (chaplet-type-task          . "#1f6fb2")
    (chaplet-type-bug           . "#b3261e")
    (chaplet-staged             . "#1f7a3d"))
  "Light-theme palette: alist of (face . foreground color).")

(defconst chaplet-face--state-faces
  '(chaplet-state-deferred chaplet-state-in-progress chaplet-state-blocked
    chaplet-state-closed chaplet-state-open)
  "Faces rendered as pills (dim background + box).")

;;; Theme detection

(defun chaplet-face--luminance (color)
  "Return the relative luminance (0..1) of COLOR string.
Returns 1.0 when COLOR cannot be parsed."
  (condition-case nil
      (let ((rgb (color-name-to-rgb color)))
        (+ (* 0.2126 (nth 0 rgb))
           (* 0.7152 (nth 1 rgb))
           (* 0.0722 (nth 2 rgb))))
    (error 1.0)))

(defun chaplet-face-dark-p ()
  "Return non-nil when the `default' face background is dark.
A nil or unspecified background counts as light."
  (let ((bg (face-attribute 'default :background nil 'default)))
    (and (stringp bg)
         (not (string= bg "unspecified-bg"))
         (< (chaplet-face--luminance bg) 0.5))))

(defun chaplet-face--dim-background (color)
  "Return a dim background color derived from COLOR.
Mixes COLOR (18%) into the `default' face background for a subtle pill."
  (let ((bg (face-attribute 'default :background nil 'default)))
    (setq bg (if (and (stringp bg) (not (string= bg "unspecified-bg")))
                 bg
               "#282c34"))
    (if (fboundp 'color-mix)
        (color-mix 'srgb color bg 0.18)
      bg)))

;;; Adaptation

(defun chaplet-face-adapt ()
  "Re-spec every chaplet face from the active dark/light palette.
Idempotent and batch-safe: only calls `face-spec-set', no display access."
  (let ((palette (if (chaplet-face-dark-p)
                     chaplet-face--dark-palette
                   chaplet-face--light-palette)))
    (dolist (entry palette)
      (let ((face (car entry))
            (color (cdr entry)))
        (face-spec-set
         face
         (if (memq face chaplet-face--state-faces)
             `((t :foreground ,color
                  :background ,(chaplet-face--dim-background color)
                  :box t))
           `((t :foreground ,color)))
         'face-defface-spec)))))

(defun chaplet-face-setup ()
  "Apply the active palette and adapt on future theme changes.
Idempotent: `after-load-theme-hook' is registered at most once."
  (chaplet-face-adapt)
  (add-hook 'after-load-theme-hook #'chaplet-face-adapt))

;;; Mappings

(defun chaplet-state-face (status)
  "Return the state face symbol for STATUS string, or nil."
  (pcase status
    ("deferred"    'chaplet-state-deferred)
    ("in_progress" 'chaplet-state-in-progress)
    ("blocked"     'chaplet-state-blocked)
    ("closed"      'chaplet-state-closed)
    ("open"        'chaplet-state-open)
    (_ nil)))

(defun chaplet-state-color (status)
  "Return the effective foreground color of STATUS's face (SVG fill).
Falls back to the dark palette color when the face has no usable
foreground (e.g. face unset in batch)."
  (let ((face (chaplet-state-face status)))
    (if (null face)
        nil
      (let ((fg (condition-case nil
                    (face-attribute face :foreground nil 'default)
                  (error nil))))
        (cond ((and (stringp fg) (not (string= fg "unspecified-fg"))) fg)
              (t (cdr (assq face chaplet-face--dark-palette))))))))

(defun chaplet-priority-face (priority)
  "Return the priority face symbol for PRIORITY (2 high, 1 med, 0 low).
Accepts numbers or numeric strings; nil for other values."
  (let ((p (if (stringp priority) (string-to-number priority) priority)))
    (pcase p
      (2 'chaplet-priority-high)
      (1 'chaplet-priority-medium)
      (0 'chaplet-priority-low)
      (_ nil))))

(defun chaplet-type-face (type)
  "Return the type face symbol for TYPE string, or nil."
  (pcase type
    ("epic" 'chaplet-type-epic)
    ("task" 'chaplet-type-task)
    ("bug"  'chaplet-type-bug)
    (_ nil)))

(provide 'chaplet-face)
;;; chaplet-face.el ends here
