;;; chaplet-graph.el --- dependency DAG → SVG render -*- lexical-binding: t; -*-

;; Render the bd dependency graph as an inline SVG image (Graphviz).
;; Falls back to raw DOT text when `dot' is unavailable.

(require 'chaplet-bd)

(defvar chaplet-graph-dot-program "dot"
  "Graphviz `dot' program (name or path).  Override for tests.")

(defun chaplet-graph--dot-available-p ()
  "Return non-nil when the Graphviz `dot' program is available."
  (and (executable-find chaplet-graph-dot-program) t))

(defun chaplet-graph--dot->svg (dot)
  "Pipe DOT (a string) through `dot -Tsvg'.  Return SVG string or nil."
  (with-temp-buffer
    (insert dot)
    (let ((exit (call-process-region (point-min) (point-max)
                                     chaplet-graph-dot-program
                                     nil t nil "-Tsvg")))
      (and (= exit 0) (buffer-string)))))

(defun chaplet-graph--render (svg)
  "Create/refresh `*chaplet:graph*' with SVG content.  Return the buffer."
  (require 'image)
  (with-current-buffer (get-buffer-create "*chaplet:graph*")
    (let ((inhibit-read-only t))
      (erase-buffer)
      (insert svg)
      (when (display-images-p) (image-mode)))
    (current-buffer)))

(defun chaplet-graph--show-dot (dot)
  "Show raw DOT in `*chaplet:graph*' (dot unavailable or failed)."
  (with-current-buffer (get-buffer-create "*chaplet:graph*")
    (let ((inhibit-read-only t))
      (erase-buffer)
      (insert dot)
      (fundamental-mode)
      (use-local-map (let ((m (make-sparse-keymap)))
                       (define-key m (kbd "q") 'quit-window)
                       m)))
    (current-buffer)))

(defun chaplet-graph (&optional include-closed)
  "Render the bd dependency DAG for the current scope.
With prefix arg INCLUDE-CLOSED (e.g. `C-u'), include closed beads."
  (interactive "P")
  (let ((dot (chaplet-bd-graph-dot
              (when include-closed '((:closed . t))))))
    (cond
     ((null dot) (message "chaplet: no graph data"))
     ((chaplet-graph--dot-available-p)
      (let ((svg (chaplet-graph--dot->svg dot)))
        (if svg
            (pop-to-buffer (chaplet-graph--render svg))
          (message "chaplet: graph render failed; showing raw DOT")
          (pop-to-buffer (chaplet-graph--show-dot dot)))))
     (t
      (message "chaplet: dot not found; showing raw DOT")
      (pop-to-buffer (chaplet-graph--show-dot dot))))))

(provide 'chaplet-graph)
;;; chaplet-graph.el ends here
