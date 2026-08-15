;;; chaplet-graph.el --- dependency DAG → SVG render -*- lexical-binding: t; -*-

;; Render the bd dependency graph as an inline SVG image with clickable
;; nodes and keyboard focus navigation (design §4.4).  Falls back to a
;; navigable text outline when images are unavailable (no display, or
;; `svg-image' returns nil — e.g. librsvg absent).
;;
;; Pure pipeline: `chaplet-graph--nodes' → bead alists to node plists,
;; `chaplet-graph--layout' → layered top-down DAG (xywh + edges),
;; `chaplet-graph--svg' → svg.el DOM object, `chaplet-graph--image-map'
;; → clickable `:map' regions.  Zero external deps.
;;
;; Buffer/navigation: `chaplet-graph' (entry), `chaplet-graph-mode'
;; minor mode binds n/p (focus next/prev), RET (open focused in
;; `chaplet-detail'), d/f (jump dependents/deps), g (refresh), c (toggle
;; closed), q (quit).  Node hot-spots bind `[ID mouse-1]' (open) and
;; `[ID mouse-2]' (dependents).  Evil-safe: bindings live in the minor
;; mode `chaplet-graph-mode', not the shadow-prone local map.

(require 'chaplet-bd)
(require 'svg)
(require 'chaplet-face)
(require 'chaplet-bar)
(require 'cl-lib)
(require 'image)

;;; ----------------------------------------------------------------------
;;; Buffer + navigation (design §4.4)
;;; ----------------------------------------------------------------------

(defvar-local chaplet-graph--nodes nil
  "Node plists (with :x :y :w :h) in the current graph buffer.")
(defvar-local chaplet-graph--edges nil
  "Edge list (FROM . TO) in the current graph buffer.")
(defvar-local chaplet-graph--focus-id nil
  "Id of the focused node in the current graph buffer.")
(defvar-local chaplet-graph--text-mode nil
  "Non-nil when the current graph buffer shows the text fallback.")
(defvar-local chaplet-graph--include-closed nil
  "Non-nil when the current graph buffer includes closed beads.")

(defvar chaplet-graph-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "n") #'chaplet-graph--focus-next)
    (define-key map (kbd "p") #'chaplet-graph--focus-prev)
    (define-key map (kbd "RET") #'chaplet-graph--open-focused)
    (define-key map (kbd "d") #'chaplet-graph--jump-dependents)
    (define-key map (kbd "f") #'chaplet-graph--jump-deps)
    (define-key map (kbd "g") #'chaplet-graph--refresh)
    (define-key map (kbd "c") #'chaplet-graph-toggle-closed)
    (define-key map (kbd "q") #'quit-window)
    map)
  "Keymap for `chaplet-graph-mode'.")

(declare-function chaplet-detail "chaplet-detail" (id))

(defvar chaplet-graph--node-bindings nil
  "Image-map event keys currently installed in `chaplet-graph-mode-map'.
Each element is a key vector `[ID mouse-1]' or `[ID mouse-2]'.")

(defvar chaplet-graph--bar-specs
  '(("n" . "next")
    ("p" . "prev")
    ("RET" . "open focused")
    ("d" . "dependents")
    ("f" . "deps")
    ("g" . "refresh")
    ("c" . "toggle closed")
    ("q" . "quit"))
  "Keybinding reference entries for the graph buffer bar (keyboard).
KEY-STRING entries are checked against `chaplet-graph-mode-map'.")

(defvar chaplet-graph--bar-extra
  '(("mouse-1" . "open node")
    ("mouse-2" . "dependents"))
  "Static reference entries for the per-node mouse hot-spots.")

(defun chaplet-graph--image-available-p ()
  "Return non-nil when inline SVG images can be displayed in this session."
  (and (display-images-p) (fboundp 'svg-image)))

(defun chaplet-graph--bind-node-events (nodes)
  "Bind `[ID mouse-1]' (open) and `[ID mouse-2]' (dependents) for NODES.
Replaces the bindings installed by the previous render."
  (dolist (key chaplet-graph--node-bindings)
    (define-key chaplet-graph-mode-map key nil))
  (setq chaplet-graph--node-bindings
        (mapcan (lambda (n)
                  (let ((id (intern (plist-get n :id))))
                    (list (vector id 'mouse-1)
                          (vector id 'mouse-2))))
                nodes))
  (dolist (key chaplet-graph--node-bindings)
    (define-key chaplet-graph-mode-map key
      (if (eq (aref key 1) 'mouse-1)
          #'chaplet-graph--open-node
        #'chaplet-graph--node-dependents))))

(defun chaplet-graph--clicked-id ()
  "Return the node id symbol of the clicked image-map hot-spot, or nil.
Extracted from `this-command-keys' — image-map clicks are composed as
`[ID mouse-N]' key sequences (elisp manual \"Image Descriptors\")."
  (let ((keys (this-command-keys-vector)))
    (when (>= (length keys) 2)
      (aref keys 0))))

(defun chaplet-graph--open-node ()
  "Open the clicked graph node in `chaplet-detail'."
  (interactive)
  (let ((id (chaplet-graph--clicked-id)))
    (if id
        (chaplet-detail (symbol-name id))
      (message "chaplet: no node at click"))))

(defun chaplet-graph--node-dependents ()
  "Focus the clicked node, then jump to its dependents."
  (interactive)
  (let ((id (chaplet-graph--clicked-id)))
    (if id
        (progn
          (setq-local chaplet-graph--focus-id (symbol-name id))
          (chaplet-graph--jump-dependents))
      (message "chaplet: no node at click"))))

(defun chaplet-graph--text-render (nodes edges focus-id)
  "Render NODES/EDGES as a navigable text outline in the current buffer.
The focused node is marked with ▶.  Same keys as the image render
(n/p/RET/d/f/g/c/q) operate through `chaplet-graph--focus-id'."
  (let ((inhibit-read-only t))
    (erase-buffer)
    (ignore edges)
    (dolist (node nodes)
      (let* ((id (plist-get node :id))
             (focused (equal id focus-id)))
        (insert (format "%s%s %s%s\n"
                        (if focused "▶ " "   ")
                        id
                        (plist-get node :title)
                        (if (plist-get node :ghost) " (ghost)" ""))))
      (dolist (dep (plist-get node :deps))
        (insert (format "    ↳ dep %s\n" dep))))
    (goto-char (point-min))))

(defun chaplet-graph--render (nodes edges focus-id)
  "Render NODES/EDGES into the current buffer.
Uses an inline SVG image with clickable `:map' hot-spots when images
are available; otherwise falls back to `chaplet-graph--text-render'.
Returns the current buffer."
  (let ((inhibit-read-only t)
        (image (and (chaplet-graph--image-available-p)
                    (svg-image (chaplet-graph--svg nodes edges focus-id)
                               :map (chaplet-graph--image-map nodes)))))
    (chaplet-graph--bind-node-events nodes)
    (erase-buffer)
    (setq-local chaplet-graph--nodes nodes)
    (setq-local chaplet-graph--edges edges)
    (setq-local chaplet-graph--focus-id focus-id)
    (setq-local chaplet-graph--text-mode (null image))
    (if image
        (progn
          (insert-image image)
          (image-mode 1))
      (chaplet-graph--text-render nodes edges focus-id))
    (chaplet-graph-mode 1)
    (chaplet-graph--update-mode-line)
    (setq-local chaplet-bar--map chaplet-graph-mode-map)
    (setq-local chaplet-bar--specs chaplet-graph--bar-specs)
    (setq-local chaplet-bar--extra chaplet-graph--bar-extra)
    (chaplet-bar--install)
    (current-buffer)))

(defun chaplet-graph--update-mode-line ()
  "Set `mode-line-process' in the current graph buffer."
  (setq mode-line-process
        (format " %s%s" (if chaplet-graph--text-mode "text" "svg")
                (if chaplet-graph--include-closed " closed" ""))))

(defun chaplet-graph--refresh ()
  "Re-fetch, re-layout and re-render the graph in the current buffer.
Preserves `chaplet-graph--focus-id' when the focused node still exists."
  (interactive)
  (let* ((keep-focus chaplet-graph--focus-id)
         (beads (chaplet-bd-graph-data chaplet-graph--include-closed)))
    (if (null beads)
        (message "chaplet: no graph data")
      (let* ((layout (chaplet-graph--layout
                      (chaplet-graph--nodes beads)))
             (nodes (car layout))
             (edges (cdr layout)))
        (setq-local chaplet-graph--nodes nodes)
        (setq-local chaplet-graph--edges edges)
        (setq-local chaplet-graph--focus-id
                   (when (member keep-focus
                                 (mapcar (lambda (n) (plist-get n :id)) nodes))
                     keep-focus))
        (chaplet-graph--render nodes edges chaplet-graph--focus-id)))))

(defun chaplet-graph-toggle-closed ()
  "Toggle whether the graph includes closed beads, then re-render."
  (interactive)
  (setq-local chaplet-graph--include-closed (not chaplet-graph--include-closed))
  (chaplet-graph--refresh))

(defun chaplet-graph--focus-relative (delta)
  "Move focus by DELTA positions in node order, cycling at the ends."
  (let* ((ids (mapcar (lambda (n) (plist-get n :id)) chaplet-graph--nodes)))
    (when ids
      (let* ((pos (or (cl-position chaplet-graph--focus-id ids :test #'equal) -1))
             (next (mod (+ pos delta) (length ids)))
             (id (nth next ids)))
        (setq-local chaplet-graph--focus-id id)
        (chaplet-graph--render chaplet-graph--nodes
                               chaplet-graph--edges id)))))

(defun chaplet-graph--focus-next ()
  "Move focus to the next node (n), re-rendering with the halo."
  (interactive)
  (chaplet-graph--focus-relative 1))

(defun chaplet-graph--focus-prev ()
  "Move focus to the previous node (p), re-rendering with the halo."
  (interactive)
  (chaplet-graph--focus-relative -1))

(defun chaplet-graph--open-focused ()
  "Open the focused node in `chaplet-detail' (RET)."
  (interactive)
  (if chaplet-graph--focus-id
      (chaplet-detail chaplet-graph--focus-id)
    (message "chaplet: no focused node")))

(defun chaplet-graph--jump-dependents ()
  "Move focus to a node that depends on the focused node (d)."
  (interactive)
  (let* ((id chaplet-graph--focus-id)
         (target (car (cl-remove-if-not
                       (lambda (e) (equal (cdr e) id))
                       chaplet-graph--edges))))
    (if target
        (progn
          (setq-local chaplet-graph--focus-id (car target))
          (chaplet-graph--render chaplet-graph--nodes
                                 chaplet-graph--edges (car target)))
      (message "chaplet: no dependents%s"
               (if id "" " (no focus)")))))

(defun chaplet-graph--jump-deps ()
  "Move focus to a dependency of the focused node (f)."
  (interactive)
  (let* ((id chaplet-graph--focus-id)
         (target (car (cl-remove-if-not
                       (lambda (e) (equal (car e) id))
                       chaplet-graph--edges))))
    (if target
        (progn
          (setq-local chaplet-graph--focus-id (cdr target))
          (chaplet-graph--render chaplet-graph--nodes
                                 chaplet-graph--edges (cdr target)))
      (message "chaplet: no deps%s"
               (if id "" " (no focus)")))))

(define-minor-mode chaplet-graph-mode
  "Minor mode for chaplet graph buffers (SVG image or text outline).
\\{chaplet-graph-mode-map}"
  :keymap chaplet-graph-mode-map)

;;;###autoload
(defun chaplet-graph (&optional include-closed)
  "Render the bd dependency DAG for the current scope.
With prefix arg INCLUDE-CLOSED (e.g. `C-u'), include closed beads."
  (interactive "P")
  (let ((buf (get-buffer-create "*chaplet:graph*")))
    (with-current-buffer buf
      (setq-local chaplet-graph--include-closed (when include-closed t))
      (chaplet-graph--refresh))
    (pop-to-buffer buf)))

;;; ----------------------------------------------------------------------
;;; Pure layout + SVG pipeline (design §4.4, §5.2-5.4)
;;; ----------------------------------------------------------------------

(defgroup chaplet-graph nil
  "Navigable dependency graph view."
  :group 'chaplet)

(defcustom chaplet-graph--x-gap 28
  "Horizontal gap between nodes in a layer (px)."
  :type 'integer
  :group 'chaplet-graph)

(defcustom chaplet-graph--y-gap 40
  "Vertical gap between layers (px)."
  :type 'integer
  :group 'chaplet-graph)

(defcustom chaplet-graph--node-h 28
  "Node height (px)."
  :type 'integer
  :group 'chaplet-graph)

(defcustom chaplet-graph--title-max 28
  "Maximum title width (columns) before truncation."
  :type 'integer
  :group 'chaplet-graph)

(defcustom chaplet-graph--pad 8
  "Horizontal padding inside a node (px)."
  :type 'integer
  :group 'chaplet-graph)

(defcustom chaplet-graph--margin 16
  "Canvas margin around the graph (px)."
  :type 'integer
  :group 'chaplet-graph)

(defun chaplet-graph--truncate (title)
  "Truncate TITLE to `chaplet-graph--title-max' columns, adding an ellipsis."
  (if (<= (string-width title) chaplet-graph--title-max)
      title
    (let ((cut (truncate-string-to-width
                title (max 1 (- chaplet-graph--title-max 1)))))
      (concat cut "…"))))

(defun chaplet-graph--node (bead)
  "Convert bead alist BEAD into a graph node plist.
Returns (:id :title :state :type :priority :deps)."
  (list :id (alist-get 'id bead)
        :title (chaplet-graph--truncate (or (alist-get 'title bead) ""))
        :state (alist-get 'status bead)
        :type (alist-get 'issue_type bead)
        :priority (alist-get 'priority bead)
        :deps (alist-get 'dependencies bead)))

(defun chaplet-graph--nodes (beads)
  "Convert BEADS (bead alists) into graph node plists."
  (mapcar #'chaplet-graph--node beads))

(defun chaplet-graph--ghost-node (id)
  "Return a ghost node plist for unknown dependency ID.
Ghost nodes carry :ghost t, closed state, and a \" (closed)\" title suffix."
  (list :id id
        :title (chaplet-graph--truncate (concat id " (closed)"))
        :state "closed"
        :type nil
        :priority nil
        :deps nil
        :ghost t))

(defun chaplet-graph--add-ghosts (nodes)
  "Return NODES plus one ghost node per dependency not in the set."
  (let* ((ids (mapcar (lambda (n) (plist-get n :id)) nodes))
         (seen (make-hash-table :test 'equal))
         ghosts)
    (dolist (n nodes)
      (dolist (dep (plist-get n :deps))
        (when (and (not (member dep ids))
                   (not (gethash dep seen)))
          (puthash dep t seen)
          (push (chaplet-graph--ghost-node dep) ghosts))))
    (append nodes (nreverse ghosts))))

(defun chaplet-graph--layers (nodes)
  "Return hash table ID → layer for NODES.
Layer is the longest path length from a root (ghost deps count as
depth 0, so a node depending on a ghost sits at layer ≥ 1)."
  (let ((layer (make-hash-table :test 'equal)))
    (let ((changed t))
      (while changed
        (setq changed nil)
        (dolist (n nodes)
          (let* ((deps (plist-get n :deps))
                 (l (if deps
                        (1+ (seq-max
                             (mapcar (lambda (d) (gethash d layer 0)) deps)))
                      0)))
            (when (/= l (gethash (plist-get n :id) layer 0))
              (puthash (plist-get n :id) l layer)
              (setq changed t))))))
    layer))

(defun chaplet-graph--node-w (node)
  "Return the layout width (px) of NODE.
Width = max(min(title-width, title-max) × 7 + pad, 90)."
  (max (+ (* (min (string-width (plist-get node :title))
                  chaplet-graph--title-max)
              7)
          chaplet-graph--pad)
       90))

(defun chaplet-graph--row-width (row)
  "Return the total width (px) of ROW (a list of nodes)."
  (if (null row)
      0
    (+ (apply #'+ (mapcar #'chaplet-graph--node-w row))
       (* chaplet-graph--x-gap (1- (length row))))))

(defun chaplet-graph--sort-by-id (nodes)
  "Return NODES sorted stably by :id."
  (sort (copy-sequence nodes)
        (lambda (a b) (string< (plist-get a :id) (plist-get b :id)))))

(defun chaplet-graph--rows (nodes layers)
  "Return alist (LAYER . NODES) for NODES, per-layer nodes sorted by :id."
  (let ((by-layer (make-hash-table :test 'eql)))
    (dolist (n nodes)
      (push n (gethash (gethash (plist-get n :id) layers 0) by-layer)))
    (let (rows)
      (maphash (lambda (layer ns)
                 (push (cons layer (chaplet-graph--sort-by-id ns)) rows))
               by-layer)
      (sort rows (lambda (a b) (< (car a) (car b)))))))

(defun chaplet-graph--layout (nodes)
  "Layered top-down DAG layout for NODES (pure, deterministic).
Returns a cons (NODES-WITH-XYWH . EDGES).  Each node plist gains
:x :y :w :h.  EDGES is a list of (FROM . TO) — FROM depends on TO
(arrow points FROM → TO, TO is drawn above).  Ghost nodes are
appended for unknown dependencies."
  (let* ((all (chaplet-graph--add-ghosts nodes))
         (layers (chaplet-graph--layers all))
         (rows (chaplet-graph--rows all layers))
         (max-row-width (if rows
                            (seq-max (mapcar (lambda (row)
                                               (chaplet-graph--row-width (cdr row)))
                                             rows))
                          0))
         edges)
    (dolist (row rows)
      (let* ((layer (car row))
             (ns (cdr row))
             (rw (chaplet-graph--row-width ns))
             (start-x (+ chaplet-graph--margin (/ (- max-row-width rw) 2)))
             (y (+ chaplet-graph--margin
                   (* layer (+ chaplet-graph--node-h chaplet-graph--y-gap)))))
        (let ((x start-x))
          (dolist (n ns)
            (plist-put n :x x)
            (plist-put n :y y)
            (plist-put n :w (chaplet-graph--node-w n))
            (plist-put n :h chaplet-graph--node-h)
            (setq x (+ x (chaplet-graph--node-w n) chaplet-graph--x-gap))))))
    (dolist (n all)
      (dolist (dep (plist-get n :deps))
        (push (cons (plist-get n :id) dep) edges)))
    (cons all (nreverse edges))))

(defun chaplet-graph--canvas-size (nodes)
  "Return (WIDTH . HEIGHT) in px covering NODES plus margin."
  (if (null nodes)
      (cons 1 1)
    (cons (+ chaplet-graph--margin
             (seq-max (mapcar (lambda (n) (+ (plist-get n :x) (plist-get n :w)))
                              nodes)))
          (+ chaplet-graph--margin
             (seq-max (mapcar (lambda (n) (+ (plist-get n :y) (plist-get n :h)))
                              nodes))))))

(defun chaplet-graph--node-color (node)
  "Return the SVG fill color for NODE from its state face."
  (or (chaplet-state-color (plist-get node :state))
      "#5c6370"))

(defun chaplet-graph--draw-node (svg node focused)
  "Draw NODE on SVG as a filled rect + id/title labels.
FOCUSED non-nil draws a 3px halo rect around the node."
  (let* ((x (plist-get node :x))
         (y (plist-get node :y))
         (w (plist-get node :w))
         (h (plist-get node :h))
         (color (chaplet-graph--node-color node))
         (id (plist-get node :id)))
    (svg-rectangle svg x y w h :fill color :id (format "node-%s" id))
    (svg-text svg id :x (+ x 4) :y (+ y 12)
              :font-size 8 :fill "#ffffff" :font-weight "bold")
    (svg-text svg (plist-get node :title) :x (+ x 4) :y (+ y 22)
              :font-size 9 :fill "#ffffff")
    (when focused
      (svg-rectangle svg (- x 2) (- y 2) (+ w 4) (+ h 4)
                     :fill "none" :stroke-width 3 :stroke-color color))))

(defun chaplet-graph--draw-edge (svg edge by-id)
  "Draw EDGE (FROM . TO) on SVG: line + arrowhead at the target top."
  (let ((src (gethash (car edge) by-id))
        (dst (gethash (cdr edge) by-id)))
    (when (and src dst)
      (let* ((x1 (+ (plist-get src :x) (/ (plist-get src :w) 2)))
             (y1 (+ (plist-get src :y) (plist-get src :h)))
             (x2 (+ (plist-get dst :x) (/ (plist-get dst :w) 2)))
             (y2 (plist-get dst :y))
             (color "#888888"))
        (svg-line svg x1 y1 x2 y2 :stroke color :stroke-width 1)
        (svg-polygon svg (list (list x2 y2)
                               (list (- x2 4) (- y2 4))
                               (list (+ x2 4) (- y2 4)))
                     :fill color)))))

(defun chaplet-graph--svg (nodes edges focus-id)
  "Return an SVG object rendering NODES and EDGES (design §4.4).
FOCUS-ID non-nil draws the 3px focus halo around that node."
  (let* ((size (chaplet-graph--canvas-size nodes))
         (svg (svg-create (car size) (cdr size)))
         (by-id (make-hash-table :test 'equal)))
    (dolist (n nodes)
      (puthash (plist-get n :id) n by-id))
    (dolist (e edges)
      (chaplet-graph--draw-edge svg e by-id))
    (dolist (n nodes)
      (chaplet-graph--draw-node svg n (equal (plist-get n :id) focus-id)))
    svg))

(defun chaplet-graph--svg-string (svg)
  "Render SVG object into an XML string."
  (with-temp-buffer
    (svg-print svg)
    (buffer-string)))

(defun chaplet-graph--image-map (nodes)
  "Return an image `:map' alist with one rect region per NODE.
Region format (elisp manual \"Image Descriptors\"): (AREA ID PLIST),
AREA = (rect . ((X0 . Y0) . (X1 . Y1))).  Click events are composed
as `[ID mouse-1]' / `[ID mouse-2]' (dispatched by the graph keymap).
Each region carries a `help-echo' tooltip."
  (mapcar
   (lambda (n)
     (let ((x1 (plist-get n :x))
           (y1 (plist-get n :y))
           (x2 (+ (plist-get n :x) (plist-get n :w)))
           (y2 (+ (plist-get n :y) (plist-get n :h))))
       (list (cons 'rect (cons (cons x1 y1) (cons x2 y2)))
             (intern (plist-get n :id))
             (list 'help-echo
                   (format "%s — %s" (plist-get n :id) (plist-get n :title))))))
   nodes))

(provide 'chaplet-graph)
;;; chaplet-graph.el ends here
