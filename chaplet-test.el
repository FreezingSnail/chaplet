;;; chaplet-test.el --- ERT tests for chaplet -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'chaplet-bd)
(require 'chaplet-face)
(require 'chaplet-bar)
(require 'chaplet-detail)
(require 'chaplet-list)
(require 'chaplet-graph)
(require 'chaplet-transient)
(require 'chaplet)

(defvar chaplet-test--root
  (file-name-directory (or load-file-name buffer-file-name default-directory))
  "Directory containing chaplet-test.el (repo root).")

(defvar chaplet-test--fake-bd
  (expand-file-name "test/fake-bd" chaplet-test--root)
  "Absolute path to the committed fake bd script.")

(ert-deftest chaplet-test-bd-filters->args ()
  "Filters map to correct bd CLI args."
  (should (equal (chaplet-bd--filters->args nil) nil))
  (should (equal (chaplet-bd--filters->args
                  '((:status . "deferred") (:label . "staged")))
                 '("--status=deferred" "--label=staged")))
  (should (equal (chaplet-bd--filters->args
                  '((:priority . 0) (:limit . 5)))
                 '("--priority=0" "--limit=5")))
  (should (equal (chaplet-bd--filters->args '((:all . t))) '("--all")))
  (should (equal (chaplet-bd--filters->args '((:all . nil))) nil))
  (should (equal (chaplet-bd--filters->args
                  '((:status . "open") (:type . "task") (:all . t)))
                 '("--status=open" "--type=task" "--all"))))

(ert-deftest chaplet-test-bd-views ()
  "Canonical view table exposes filters and names."
  (should (equal (chaplet-bd--view-filters 'inbox)
                 '((:status . "deferred") (:label . "staged"))))
  (should (equal (chaplet-bd--view-filters 'all) '((:all . t))))
  (should (equal (chaplet-bd--view-filters 'bogus) nil))
  (should (equal (chaplet-bd--view-names)
                 '(inbox open in-progress blocked closed all))))

(ert-deftest chaplet-test-bd-filters->expr ()
  "`chaplet-bd--filters->expr' composes query clauses, skipping booleans."
  (should (equal (chaplet-bd--filters->expr
                  '((:status . "deferred") (:label . "staged")))
                 "status=deferred AND label=staged"))
  (should (equal (chaplet-bd--filters->expr '((:type . "task"))) "type=task"))
  (should (equal (chaplet-bd--filters->expr '((:priority . 2)))
                 "priority=2"))
  (should (equal (chaplet-bd--filters->expr '((:all . t))) ""))
  (should (equal (chaplet-bd--filters->expr
                  '((:status . "open") (:all . t) (:type . "task")))
                 "status=open AND type=task")))

(ert-deftest chaplet-test-bd-list ()
  "`chaplet-bd-list' returns parsed bead alists."
  (let ((chaplet-bd-program chaplet-test--fake-bd))
    (let ((beads (chaplet-bd-list)))
      (should (= (length beads) 2))
      (should (equal (alist-get 'id (car beads)) "bd-1"))
      (should (equal (alist-get 'title (car beads)) "one"))
      (should (equal (alist-get 'status (car beads)) "open"))
      (should (equal (alist-get 'priority (car beads)) 2))
      (should (equal (alist-get 'owner (cadr beads)) "bob"))
      (should (equal (alist-get 'labels (cadr beads)) '("staged")))
      (should (equal (alist-get 'defer_until (cadr beads)) "2026-02-01"))
      (should (equal (alist-get 'design (cadr beads)) "design2")))))

(ert-deftest chaplet-test-bd-show ()
  "`chaplet-bd-show' parses a single object into a bead alist."
  (let ((chaplet-bd-program chaplet-test--fake-bd))
    (let ((bead (chaplet-bd-show "bd-1")))
      (should (equal (alist-get 'id bead) "bd-1"))
      (should (equal (alist-get 'design bead) "design1"))
      (should (equal (alist-get 'acceptance bead) "acc1"))
      (should (equal (alist-get 'owner bead) "alice")))))

(ert-deftest chaplet-test-bd-query ()
  "`chaplet-bd-query' returns parsed bead alists."
  (let ((chaplet-bd-program chaplet-test--fake-bd))
    (let ((beads (chaplet-bd-query "status=deferred AND label=staged")))
      (should (= (length beads) 1))
      (should (equal (alist-get 'id (car beads)) "bd-2"))
      (should (equal (alist-get 'status (car beads)) "deferred")))))

(ert-deftest chaplet-test-bd-graph-dot ()
  "`chaplet-bd-graph-dot' returns a DOT string."
  (let ((chaplet-bd-program chaplet-test--fake-bd))
    (let ((dot (chaplet-bd-graph-dot)))
      (should (stringp dot))
      (should (string-match-p "digraph" dot)))))

(ert-deftest chaplet-test-bd-undefer ()
  "`chaplet-bd-undefer' returns t on success."
  (let ((chaplet-bd-program chaplet-test--fake-bd))
    (should (eq (chaplet-bd-undefer "bd-1") t))))

(ert-deftest chaplet-test-bd-label-remove ()
  "`chaplet-bd-label-remove' returns t on success."
  (let ((chaplet-bd-program chaplet-test--fake-bd))
    (should (eq (chaplet-bd-label-remove "bd-1" "staged") t))))

(ert-deftest chaplet-test-bd-create ()
  "`chaplet-bd-create' returns the new id."
  (let ((chaplet-bd-program chaplet-test--fake-bd))
    (should (equal (chaplet-bd-create "my title" "task" "desc") "bd-99"))))

(ert-deftest chaplet-test-bd-write-failure ()
  "Writes return nil when bd exits non-zero."
  (cl-letf (((symbol-function 'chaplet-bd--invoke)
             (lambda (_args) (cons 1 ""))))
    (should (eq (chaplet-bd-defer "bd-1") nil))
    (should (eq (chaplet-bd-undefer "bd-1") nil))
    (should (eq (chaplet-bd-label-remove "bd-1" "staged") nil))))

(ert-deftest chaplet-test-bd-comment-args ()
  "`chaplet-bd-comment' assembles correct args."
  (let ((captured nil))
    (cl-letf (((symbol-function 'chaplet-bd--invoke)
               (lambda (args) (setq captured args) (cons 0 ""))))
      (chaplet-bd-comment "bd-1" "hello world")
      (should (equal captured '("comment" "bd-1" "hello world"))))))

(ert-deftest chaplet-test-bd-update-args ()
  "`chaplet-bd-update-design' and friends assemble correct args."
  (let ((captured nil))
    (cl-letf (((symbol-function 'chaplet-bd--invoke)
               (lambda (args) (setq captured args) (cons 0 ""))))
      (chaplet-bd-update-design "bd-1" "the design")
      (should (equal captured '("update" "bd-1" "--design" "the design")))
      (chaplet-bd-update-acceptance "bd-1" "the acc")
      (should (equal captured '("update" "bd-1" "--acceptance" "the acc")))
      (chaplet-bd-label "bd-1" "staged")
      (should (equal captured '("label" "add" "bd-1" "staged")))
      (chaplet-bd-label-remove "bd-1" "staged")
      (should (equal captured '("label" "remove" "bd-1" "staged")))
      (chaplet-bd-undefer "bd-1")
      (should (equal captured '("undefer" "bd-1")))
      (chaplet-bd-defer "bd-1")
      (should (equal captured '("defer" "bd-1"))))))

(ert-deftest chaplet-test-bd-root ()
  "`chaplet-bd--root' returns the chaplet repo root when run there."
  (let ((default-directory chaplet-test--root))
    (should (file-equal-p (chaplet-bd--root) chaplet-test--root))))

(ert-deftest chaplet-test-list-staged-p ()
  "`chaplet-list--staged-p' detects staged beads."
  (should (chaplet-list--staged-p
           '((status . "deferred") (labels . ("staged")))))
  (should-not (chaplet-list--staged-p
               '((status . "deferred") (labels . ("x")))))
  (should-not (chaplet-list--staged-p
               '((status . "open") (labels . ("staged")))))
  ;; labels absent (real bd list JSON) -> approximate deferred.
  (should (chaplet-list--staged-p
           '((status . "deferred") (labels . nil))))
  (should-not (chaplet-list--staged-p
               '((status . "open") (labels . nil)))))

(ert-deftest chaplet-test-list-view-query ()
  "`chaplet-list--view-query' maps views to bd query expressions."
  (should (equal (chaplet-list--view-query 'inbox)
                 "status=deferred AND label=staged"))
  (should (equal (chaplet-list--view-query 'open) "status=open"))
  (should (equal (chaplet-list--view-query 'in-progress) "status=in_progress"))
  (should (equal (chaplet-list--view-query 'blocked) "status=blocked"))
  (should (equal (chaplet-list--view-query 'closed) "status=closed"))
  (should (null (chaplet-list--view-query 'all))))

(ert-deftest chaplet-test-list-format ()
  "`chaplet-list--format' declares the expected columns."
  (should (equal chaplet-list--format
                 [("ID" 12) ("Type" 10) ("State" 12) ("P" 3)
                  ("Staged" 7) ("Title" 60)])))

(ert-deftest chaplet-test-list-entry ()
  "`chaplet-list--entry' renders a bead alist into the table row shape."
  (let ((bead '((id . "bd-1") (title . "Do thing") (status . "deferred")
                (priority . 2) (issue_type . "task") (labels . ("staged")))))
    (let ((entry (chaplet-list--entry bead)))
      (should (equal (car entry) "bd-1"))
      (let ((row (cadr entry)))
        (should (vectorp row))
        (should (equal (substring-no-properties (aref row 0)) "bd-1"))
        (should (equal (substring-no-properties (aref row 1)) "task"))
        (should (equal (substring-no-properties (aref row 2)) "deferred"))
        (should (equal (substring-no-properties (aref row 3)) "●2"))
        (should (equal (substring-no-properties (aref row 4)) "✔"))
        (should (equal (aref row 5) "Do thing"))))))

(ert-deftest chaplet-test-list-entry-not-staged ()
  "Staged? column is empty for non-staged beads; P0 renders as \"·0\"."
  (let ((bead '((id . "bd-3") (title . "x") (status . "open")
                (priority . 0) (issue_type . "bug") (labels . nil))))
    (let ((entry (chaplet-list--entry bead)))
      (should (equal (substring-no-properties (aref (cadr entry) 3)) "·0"))
      (should (equal (aref (cadr entry) 4) "")))))

(ert-deftest chaplet-test-list-entry-faces ()
  "`chaplet-list--entry' propertizes ID/state/priority/type/staged with faces."
  (let* ((bead '((id . "bd-1") (title . "Do thing") (status . "deferred")
                 (priority . 2) (issue_type . "task") (labels . ("staged"))))
         (row (cadr (chaplet-list--entry bead))))
    (should (eq (get-text-property 0 'face (aref row 0)) 'chaplet-id))
    (should (eq (get-text-property 0 'face (aref row 1)) 'chaplet-type-task))
    (should (eq (get-text-property 0 'face (aref row 2)) 'chaplet-state-deferred))
    (should (eq (get-text-property 0 'face (aref row 3)) 'chaplet-priority-high))
    (should (eq (get-text-property 0 'face (aref row 4)) 'chaplet-staged))))

(ert-deftest chaplet-test-list-priority-dot ()
  "`chaplet-list--priority-dot' renders dot+number with the priority face."
  (should (equal (substring-no-properties (chaplet-list--priority-dot 2)) "●2"))
  (should (eq (get-text-property 0 'face (chaplet-list--priority-dot 2))
              'chaplet-priority-high))
  (should (equal (substring-no-properties (chaplet-list--priority-dot 1)) "·1"))
  (should (eq (get-text-property 0 'face (chaplet-list--priority-dot 1))
              'chaplet-priority-medium))
  (should (equal (substring-no-properties (chaplet-list--priority-dot 0)) "·0"))
  (should (eq (get-text-property 0 'face (chaplet-list--priority-dot 0))
              'chaplet-priority-low))
  (should (equal (chaplet-list--priority-dot nil) "")))

(ert-deftest chaplet-test-list-modeline ()
  "`chaplet-list--modeline' reports view and open/blocked counts."
  (let ((chaplet-list--current-view 'open)
        (tabulated-list-entries
         '(("bd-1" ["" "" "open" "" "" "one"])
           ("bd-2" ["" "" "open" "" "" "two"])
           ("bd-3" ["" "" "blocked" "" "" "three"])
           ("bd-4" ["" "" "closed" "" "" "four"]))))
    (let ((s (chaplet-list--modeline)))
      (should (string-match-p "chaplet open" s))
      (should (string-match-p "4 beads" s))
      (should (string-match-p "2 open" s))
      (should (string-match-p "1 blocked" s)))))

(ert-deftest chaplet-test-list-mouse-1 ()
  "[mouse-1] in `chaplet-list-mode-map' opens the bead at point."
  (should (eq (lookup-key chaplet-list-mode-map [mouse-1])
              'chaplet-list-open)))

(ert-deftest chaplet-test-list-buffer-style ()
  "`chaplet-list-mode' enables hl-line, sets a plain-string modeline, remaps header."
  (cl-letf (((symbol-function 'chaplet-list--fetch) (lambda (_view) nil)))
    (with-temp-buffer
      (chaplet-list-mode)
      (should (bound-and-true-p hl-line-mode))
      (should (stringp mode-line-process))
      (should (string-match-p "^chaplet inbox" mode-line-process))
      (should (equal mode-line-process chaplet-list--modeline-string))
      (let ((repl (cdr (assq 'header-line face-remapping-alist))))
        (should repl)
        (should (cl-some (lambda (f) (or (eq f 'chaplet-header)
                                          (and (consp f)
                                               (memq 'chaplet-header f))))
                         repl))))))

(ert-deftest chaplet-test-list-refresh-caches-modeline ()
  "`chaplet-list-refresh' computes counts once into a cached plain string
and points `mode-line-process' at it (no per-redisplay :eval)."
  (cl-letf (((symbol-function 'chaplet-list--fetch)
             (lambda (_view)
               (list '((id . "bd-1") (title . "one") (status . "open"))
                     '((id . "bd-2") (title . "two") (status . "open"))
                     '((id . "bd-3") (title . "three") (status . "blocked"))
                     '((id . "bd-4") (title . "four") (status . "closed"))))))
    (with-temp-buffer
      (chaplet-list-mode)
      (setq chaplet-list--current-view 'all)
      (chaplet-list-refresh)
      (should (stringp chaplet-list--modeline-string))
      (should (stringp mode-line-process))
      (should (equal mode-line-process chaplet-list--modeline-string))
      (should (string-match-p "chaplet all" chaplet-list--modeline-string))
      (should (string-match-p "4 beads" chaplet-list--modeline-string))
      (should (string-match-p "2 open" chaplet-list--modeline-string))
      (should (string-match-p "1 blocked" chaplet-list--modeline-string)))))

(ert-deftest chaplet-test-list-open-delegates ()
  "`chaplet-list-open' calls `chaplet-detail' when defined."
  (let ((called nil))
    (cl-letf (((symbol-function 'chaplet-detail)
               (lambda (id) (setq called id))))
      (chaplet-list-open "bd-7")
      (should (equal called "bd-7")))))

(ert-deftest chaplet-test-list-open-fallback ()
  "Without `chaplet-detail', `chaplet-list-open' shows raw bd output."
  (let ((chaplet-bd-program chaplet-test--fake-bd))
    (cl-letf (((symbol-function 'chaplet-detail) nil))
      (chaplet-list-open "bd-1")
      (should (get-buffer "*chaplet:show bd-1*"))
      (should (with-current-buffer "*chaplet:show bd-1*"
                (string-match-p "one" (buffer-string)))))))

(ert-deftest chaplet-test-list-filters->query ()
  "`chaplet-list--filters->query' composes filter clauses into a query."
  (should (equal (chaplet-list--filters->query "status=open" nil)
                 "status=open"))
  (should (equal (chaplet-list--filters->query "status=open" '((:type . "task")))
                 "status=open AND type=task"))
  (should (equal (chaplet-list--filters->query
                  "status=open" '((:type . "task") (:label . "staged")))
                 "status=open AND type=task AND label=staged")))

(ert-deftest chaplet-test-bd-comments ()
  "`chaplet-bd-comments' returns parsed comment alists."
  (let ((chaplet-bd-program chaplet-test--fake-bd))
    (let ((comments (chaplet-bd-comments "bd-1")))
      (should (= (length comments) 1))
      (should (equal (alist-get 'author (car comments)) "alice"))
      (should (equal (alist-get 'text (car comments)) "nice bead")))))

(defvar chaplet-test--detail-bead
  '((id . "bd-9")
    (title . "sample bead")
    (description . "Some **markdown** body.\n\n- item one")
    (status . "open")
    (priority . 2)
    (issue_type . "task")
    (owner . "carol")
    (labels . ("staged" "ui"))
    (design . "## Design doc\n\nThe design.")
    (acceptance . "- [ ] works")
    (created_at . "2026-01-01T00:00:00Z")
    (comments . (((author . "alice") (text . "first comment"))
                 ((author . "bob") (text . "second comment")))))
  "Fake bead alist for detail rendering tests.")

(ert-deftest chaplet-test-detail-render ()
  "`chaplet-detail--render' emits header + sections as markdown."
  (let ((s (chaplet-detail--render chaplet-test--detail-bead)))
    (should (string-match-p "^# sample bead" s))
    (should (string-match-p "\\*id:\\* bd-9" s))
    (should (string-match-p "\\*status:\\* open" s))
    (should (string-match-p "\\*priority:\\* 2" s))
    (should (string-match-p "\\*type:\\* task" s))
    (should (string-match-p "\\*owner:\\* carol" s))
    (should (string-match-p "\\*labels:\\* staged, ui" s))
    (should (string-match-p "## Description" s))
    (should (string-match-p "Some \\*\\*markdown\\*\\* body." s))
    (should (string-match-p "## Design" s))
    (should (string-match-p "## Acceptance" s))
    (should (string-match-p "## Comments" s))
    (should (string-match-p "- \\*\\*alice\\*\\* — first comment" s))
    (should (string-match-p "- \\*\\*bob\\*\\* — second comment" s))))

(ert-deftest chaplet-test-detail-render-empty ()
  "Sections with nil/blank content are omitted."
  (let ((s (chaplet-detail--render '((id . "bd-9") (title . "t")))))
    (should (string-match-p "^# t" s))
    (should-not (string-match-p "## Description" s))
    (should-not (string-match-p "## Design" s))
    (should-not (string-match-p "## Acceptance" s))
    (should-not (string-match-p "## Comments" s))))

(ert-deftest chaplet-test-detail-buffer ()
  "`chaplet-detail' builds a read-only buffer with rendered markdown."
  (let ((chaplet-bd-program chaplet-test--fake-bd))
    (chaplet-detail "bd-1")
    (should (equal (buffer-name) chaplet-detail--buffer-name))
    (should buffer-read-only)
    (should (string-match-p "# one" (buffer-string)))
    (should (string-match-p "## Description" (buffer-string)))
    (should (string-match-p "## Design" (buffer-string)))
    (should (string-match-p "## Acceptance" (buffer-string)))
    (should (string-match-p "## Comments" (buffer-string)))
    (should (string-match-p "- \\*\\*alice\\*\\* — nice bead" (buffer-string)))
    (kill-buffer)))

(ert-deftest chaplet-test-detail-buffer-reused ()
  "`chaplet-detail' reuses one shared buffer for every bead."
  (let ((chaplet-bd-program chaplet-test--fake-bd))
    (chaplet-detail "bd-1")
    (let ((win (selected-window)))
      (chaplet-detail "bd-2")
      (should (eq (selected-window) win))
      (should (equal (buffer-name) chaplet-detail--buffer-name))
      (should (string-match-p "# two" (buffer-string)))
      (should-not (string-match-p "# one" (buffer-string))))
    (kill-buffer chaplet-detail--buffer-name)))

(ert-deftest chaplet-test-detail-mode-no-markdown ()
  "Mode falls back to fundamental + font-lock without markdown-mode."
  (cl-letf (((symbol-function 'require)
             (lambda (_feature &rest _) nil)))
    (with-temp-buffer
      (should (eq (chaplet-detail--activate-major-mode) 'fundamental-mode))
      (should (eq major-mode 'fundamental-mode)))))

(ert-deftest chaplet-test-graph-render ()
  "`chaplet-graph--render' builds the graph text fallback in the current buffer."
  (with-temp-buffer
    (let* ((f (chaplet-test--graph-fixture))
           (buf (chaplet-graph--render (car f) (cdr f) nil)))
      (should (eq buf (current-buffer)))
      (should chaplet-graph--text-mode)
      (should (string-match-p "bd-1" (buffer-string)))
      (should (string-match-p "missing-dep" (buffer-string))))))

(ert-deftest chaplet-test-transient-actions-for-state ()
  "`chaplet-transient--actions-for-state' maps states to allowed actions."
  (should (equal (chaplet-transient--actions-for-state "deferred")
                 '(approve reject comment edit-design)))
  (should (equal (chaplet-transient--actions-for-state "open")
                 '(comment edit-design new)))
  (should (equal (chaplet-transient--actions-for-state "in_progress")
                 '(comment)))
  (should (equal (chaplet-transient--actions-for-state "blocked")
                 '(comment)))
  (should (equal (chaplet-transient--actions-for-state "closed")
                 '(comment)))
  (should (equal (chaplet-transient--actions-for-state nil)
                 '(comment)))
  (should (memq 'approve (chaplet-transient--actions-for-state "deferred")))
  (should (memq 'reject (chaplet-transient--actions-for-state "deferred")))
  (should-not (memq 'approve (chaplet-transient--actions-for-state "closed")))
  (should-not (memq 'new (chaplet-transient--actions-for-state "closed"))))

(ert-deftest chaplet-test-transient-action-visible-p ()
  "`chaplet-transient--action-visible-p' respects the captured state."
  (let ((chaplet-transient--state "deferred"))
    (should (chaplet-transient--action-visible-p 'approve))
    (should (chaplet-transient--action-visible-p 'reject))
    (should-not (chaplet-transient--action-visible-p 'new)))
  (let ((chaplet-transient--state "closed"))
    (should (chaplet-transient--action-visible-p 'comment))
    (should-not (chaplet-transient--action-visible-p 'approve))
    (should-not (chaplet-transient--action-visible-p 'edit-design))))

(ert-deftest chaplet-test-transient-approve ()
  "`chaplet-approve' undefer's the bead at point, strips the staged
label, and refreshes all chaplet buffers."
  (let (undefer-id removed-id removed-label refreshed)
    (cl-letf (((symbol-function 'chaplet-bd-undefer)
               (lambda (id) (setq undefer-id id) t))
              ((symbol-function 'chaplet-bd-label-remove)
               (lambda (id label) (setq removed-id id removed-label label) t))
              ((symbol-function 'chaplet-refresh-all)
               (lambda () (setq refreshed t)))
              ((symbol-function 'chaplet-transient--id-at-point)
               (lambda () "bd-1")))
      (chaplet-approve)
      (should (equal undefer-id "bd-1"))
      (should (equal removed-id "bd-1"))
      (should (equal removed-label chaplet-staged-label))
      (should refreshed))))

(ert-deftest chaplet-test-transient-reject ()
  "`chaplet-reject' prompts feedback and comments \"rejected: <fb>\"."
  (let (commented-id commented-text)
    (cl-letf (((symbol-function 'read-string)
               (lambda (&rest _) "needs work"))
              ((symbol-function 'chaplet-bd-comment)
               (lambda (id text) (setq commented-id id commented-text text) t))
              ((symbol-function 'chaplet-refresh-all)
               (lambda () nil))
              ((symbol-function 'chaplet-transient--id-at-point)
               (lambda () "bd-1")))
      (chaplet-reject)
      (should (equal commented-id "bd-1"))
      (should (equal commented-text "rejected: needs work")))))

(ert-deftest chaplet-test-transient-comment ()
  "`chaplet-comment' comments the bead at point."
  (let (commented-id commented-text)
    (cl-letf (((symbol-function 'read-string)
               (lambda (&rest _) "looks good"))
              ((symbol-function 'chaplet-bd-comment)
               (lambda (id text) (setq commented-id id commented-text text) t))
              ((symbol-function 'chaplet-refresh-all)
               (lambda () nil))
              ((symbol-function 'chaplet-transient--id-at-point)
               (lambda () "bd-1")))
      (chaplet-comment)
      (should (equal commented-id "bd-1"))
      (should (equal commented-text "looks good")))))

(ert-deftest chaplet-test-transient-edit-design ()
  "`chaplet-edit-design' updates --design for the bead at point."
  (let (design-id design-text)
    (cl-letf (((symbol-function 'read-string)
               (lambda (&rest _) "the new design"))
              ((symbol-function 'chaplet-bd-update-design)
               (lambda (id design) (setq design-id id design-text design) t))
              ((symbol-function 'chaplet-refresh-all)
               (lambda () nil))
              ((symbol-function 'chaplet-transient--id-at-point)
               (lambda () "bd-1")))
      (chaplet-edit-design)
      (should (equal design-id "bd-1"))
      (should (equal design-text "the new design")))))

(ert-deftest chaplet-test-transient-new ()
  "`chaplet-new' prompts and calls `chaplet-bd-create' with captured args."
  (let (created)
    (cl-letf (((symbol-function 'read-string)
               (lambda (prompt &rest _)
                 (pcase prompt
                   ("Title: " "my bead")
                   ("Type (task/bug/feature/epic): " "task")
                   ("Description: " "the desc"))))
              ((symbol-function 'chaplet-bd-create)
               (lambda (title type desc)
                 (setq created (list title type desc)) "bd-99"))
              ((symbol-function 'chaplet-refresh-all)
               (lambda () nil)))
      (chaplet-new)
      (should (equal created '("my bead" "task" "the desc"))))))

(ert-deftest chaplet-test-transient-refresh ()
  "`chaplet-refresh' refreshes all chaplet buffers."
  (let ((refreshed nil))
    (cl-letf (((symbol-function 'chaplet-refresh-all)
               (lambda () (setq refreshed t))))
      (chaplet-refresh)
      (should refreshed))))

(ert-deftest chaplet-test-refresh-all-refreshes-every-view ()
  "`chaplet-refresh-all' refreshes a live list, detail, and graph buffer."
  (let (list-refreshed detail-refreshed graph-refreshed)
    (with-current-buffer (get-buffer-create chaplet-list--buffer-name)
      (chaplet-list-mode))
    (unwind-protect
        (progn
          (cl-letf (((symbol-function 'chaplet-list-refresh)
                     (lambda () (setq list-refreshed t)))
                    ((symbol-function 'chaplet-detail--populate)
                     (lambda (_id) (setq detail-refreshed t)))
                    ((symbol-function 'chaplet-graph--refresh)
                     (lambda () (setq graph-refreshed t))))
            (with-current-buffer (get-buffer-create chaplet-detail--buffer-name)
              (chaplet-detail-mode 1)
              (setq-local chaplet-detail--id "bd-1"))
            (with-current-buffer (get-buffer-create "*chaplet:graph*")
              (chaplet-graph-mode))
            (chaplet-refresh-all)
            (should list-refreshed)
            (should detail-refreshed)
            (should graph-refreshed)))
      (kill-buffer chaplet-list--buffer-name)
      (kill-buffer chaplet-detail--buffer-name)
      (kill-buffer "*chaplet:graph*"))))

(ert-deftest chaplet-test-refresh-all-fallback-current-list ()
  "Without a dedicated list buffer, `chaplet-refresh-all' refreshes the
current buffer when it is a chaplet list."
  (let ((refreshed nil))
    (cl-letf (((symbol-function 'chaplet-list--fetch) (lambda (_view) nil))
              ((symbol-function 'chaplet-refresh-aux-buffers) (lambda () nil)))
      (with-temp-buffer
        (chaplet-list-mode)
        (cl-letf (((symbol-function 'chaplet-list-refresh)
                   (lambda () (setq refreshed t))))
          (chaplet-refresh-all)
          (should refreshed))))))

(ert-deftest chaplet-test-refresh-on-focus-stale ()
  "`chaplet--refresh-on-focus' refreshes when last fetch is older than
`chaplet-refresh-delay' (stale buffer picked up on return)."
  (let ((chaplet-auto-refresh t)
        (refreshed nil))
    (cl-letf (((symbol-function 'chaplet-list--fetch) (lambda (_view) nil))
              ((symbol-function 'chaplet-list-refresh)
               (lambda () (setq refreshed t))))
      (with-temp-buffer
        (chaplet-list-mode)
        (setq-local chaplet--last-fetch
                    (time-subtract (current-time) 10))
        (setq refreshed nil)
        (chaplet--refresh-on-focus (selected-window))
        (should refreshed)))))

(ert-deftest chaplet-test-refresh-on-focus-recent ()
  "`chaplet--refresh-on-focus' skips a buffer fetched less than
`chaplet-refresh-delay' seconds ago."
  (let ((chaplet-auto-refresh t)
        (refreshed nil))
    (cl-letf (((symbol-function 'chaplet-list--fetch) (lambda (_view) nil))
              ((symbol-function 'chaplet-list-refresh)
               (lambda () (setq refreshed t))))
      (with-temp-buffer
        (chaplet-list-mode)
        (chaplet--mark-fetch)
        (setq refreshed nil)
        (chaplet--refresh-on-focus (selected-window))
        (should-not refreshed)))))

(ert-deftest chaplet-test-refresh-on-focus-never-fetched ()
  "A chaplet buffer that has never fetched is stale, so focus refreshes."
  (let ((chaplet-auto-refresh t)
        (refreshed nil))
    (cl-letf (((symbol-function 'chaplet-list--fetch) (lambda (_view) nil))
              ((symbol-function 'chaplet-list-refresh)
               (lambda () (setq refreshed t))))
      (with-temp-buffer
        (chaplet-list-mode)
        (setq-local chaplet--last-fetch nil)
        (setq refreshed nil)
        (chaplet--refresh-on-focus (selected-window))
        (should refreshed)))))

(ert-deftest chaplet-test-refresh-on-focus-disabled ()
  "`chaplet--refresh-on-focus' is a no-op when `chaplet-auto-refresh' is nil."
  (let ((chaplet-auto-refresh nil)
        (refreshed nil))
    (cl-letf (((symbol-function 'chaplet-list--fetch) (lambda (_view) nil))
              ((symbol-function 'chaplet-list-refresh)
               (lambda () (setq refreshed t))))
      (with-temp-buffer
        (chaplet-list-mode)
        (setq-local chaplet--last-fetch
                    (time-subtract (current-time) 10))
        (setq refreshed nil)
        (chaplet--refresh-on-focus (selected-window))
        (should-not refreshed)))))


(ert-deftest chaplet-test-refresh-timer-schedules-ticks ()
  "`chaplet--ensure-refresh-timer' installs the configured periodic timer."
  (let ((chaplet-auto-refresh t)
        (chaplet-refresh-interval 5)
        (chaplet--refresh-timer nil))
    (unwind-protect
        (progn
          (chaplet--ensure-refresh-timer)
          (should (timerp chaplet--refresh-timer))
          (should (eq (timer--function chaplet--refresh-timer)
                      #'chaplet--refresh-tick)))
      (when (timerp chaplet--refresh-timer)
        (cancel-timer chaplet--refresh-timer)))))

(ert-deftest chaplet-test-refresh-tick-refreshes-only-stale-visible-buffers ()
  "A tick refreshes stale visible buffers, never hidden Chaplet buffers."
  (let ((chaplet-auto-refresh t)
        (visible (generate-new-buffer " *chaplet visible*"))
        (hidden (generate-new-buffer " *chaplet hidden*"))
        refreshed)
    (unwind-protect
        (progn
          (dolist (buffer (list visible hidden))
            (with-current-buffer buffer
              (chaplet-list-mode)
              (setq-local chaplet--last-fetch
                          (time-subtract (current-time) 10))))
          (cl-letf (((symbol-function 'chaplet--visible-buffers)
                     (lambda () (list visible)))
                    ((symbol-function 'chaplet--refresh-buffer)
                     (lambda () (push (current-buffer) refreshed))))
            (chaplet--refresh-tick))
          (should (equal refreshed (list visible))))
      (mapc (lambda (buffer)
              (when (buffer-live-p buffer) (kill-buffer buffer)))
            (list visible hidden)))))

(ert-deftest chaplet-test-list-refresh-skips-unchanged-render ()
  "Unchanged list data is fetched but does not redraw the table."
  (let ((beads (list '((id . "bd-1") (title . "one") (status . "open"))))
        (prints 0))
    (cl-letf (((symbol-function 'chaplet-list--fetch) (lambda (_view) beads))
              ((symbol-function 'tabulated-list-print)
               (lambda (&rest _) (cl-incf prints))))
      (with-temp-buffer
        (chaplet-list-mode)
        (setq prints 0)
        (chaplet-list-refresh)
        (should (= prints 0))))))

(ert-deftest chaplet-test-graph-refresh-skips-unchanged-render ()
  "Unchanged graph data skips layout and render work."
  (let ((renders 0))
    (cl-letf (((symbol-function 'chaplet-bd-graph-data)
               (lambda (_filters)
                 (symbol-value 'chaplet-test--graph-beads)))
              ((symbol-function 'chaplet-graph--render)
               (lambda (&rest _) (cl-incf renders))))
      (with-temp-buffer
        (setq-local chaplet-graph--view 'all)
        (chaplet-graph--refresh)
        (chaplet-graph--refresh)
        (should (= renders 1))))))
(ert-deftest chaplet-test-refresh-marks-fetch ()
  "Every list refresh stamps `chaplet--last-fetch' in the buffer."
  (cl-letf (((symbol-function 'chaplet-list--fetch) (lambda (_view) nil)))
(with-temp-buffer
        (chaplet-list-mode)
        (let ((first chaplet--last-fetch))
          (should first)                    ; mode init fetched + marked
          (sleep-for 0.01)
          (chaplet-list-refresh)
          (should (time-less-p first chaplet--last-fetch))))))

(ert-deftest chaplet-test-detail-populate-marks-fetch ()
  "`chaplet-detail--populate' stamps `chaplet--last-fetch' in the buffer."
  (cl-letf (((symbol-function 'chaplet-bd-show)
             (lambda (_id) '((id . "bd-1") (title . "one"))))
            ((symbol-function 'chaplet-bd-comments)
             (lambda (_id) nil)))
    (with-temp-buffer
      (chaplet-detail--populate "bd-1")
      (should chaplet--last-fetch))))

(ert-deftest chaplet-test-graph-refresh-marks-fetch ()
  "`chaplet-graph--refresh' stamps `chaplet--last-fetch' in the buffer."
  (cl-letf (((symbol-function 'chaplet-bd-graph-data)
             (lambda (_filters) nil)))
    (with-temp-buffer
      (setq-local chaplet-graph--view 'all)
      (chaplet-graph--refresh)
      (should chaplet--last-fetch))))

(ert-deftest chaplet-test-list-set-view-single-fetch ()
  "`chaplet-list-set-view' triggers exactly one bd fetch: the focus hook
that fires when the buffer is shown is debounced by `chaplet--last-fetch'."
  :tags '(:chaplet)
  (let ((fetches 0))
    (cl-letf (((symbol-function 'chaplet-bd-query)
               (lambda (_q) (cl-incf fetches) nil)))
      (unwind-protect
          (progn
            (chaplet-list-set-view 'inbox)
            (should (= fetches 1))
            (chaplet-list-set-view 'open)
            (should (= fetches 2)))
        (kill-buffer "*chaplet*")))))

(ert-deftest chaplet-test-transient-graph-delegates ()
  "`chaplet-graph' is fboundp (graph module); the menu delegates to it."
  (should (fboundp 'chaplet-graph)))

(ert-deftest chaplet-test-transient-detail-approve ()
  "`chaplet-transient-approve' undefer's an explicit id, strips the
staged label, and refreshes all chaplet buffers."
  (let (undefer-id removed-id removed-label refreshed)
    (cl-letf (((symbol-function 'chaplet-bd-undefer)
               (lambda (id) (setq undefer-id id) t))
              ((symbol-function 'chaplet-bd-label-remove)
               (lambda (id label) (setq removed-id id removed-label label) t))
              ((symbol-function 'chaplet-refresh-all)
               (lambda () (setq refreshed t))))
      (chaplet-transient-approve "bd-7")
      (should (equal undefer-id "bd-7"))
      (should (equal removed-id "bd-7"))
      (should (equal removed-label chaplet-staged-label))
      (should refreshed))))

(ert-deftest chaplet-test-entry-opens-inbox ()
  "`chaplet' opens the inbox (staged) view."
  :tags '(:chaplet)
  (let (called)
    (cl-letf (((symbol-function 'chaplet-list-set-view)
               (lambda (view) (setq called view))))
      (chaplet)
      (should (eq called 'inbox)))))

(ert-deftest chaplet-test-mode-map ()
  "`chaplet-mode-map' binds C-c b b → chaplet and C-c b s → chaplet-graph."
  :tags '(:chaplet)
  (should (eq (lookup-key chaplet-mode-map (kbd "C-c b b")) 'chaplet))
  (should (eq (lookup-key chaplet-mode-map (kbd "C-c b s")) 'chaplet-graph)))

(ert-deftest chaplet-test-mode-enable ()
  "`chaplet-mode' is a global minor mode that toggles on/off."
  :tags '(:chaplet)
  (unwind-protect
      (progn
        (chaplet-mode 1)
        (should chaplet-mode)
        (chaplet-mode -1)
        (should (not chaplet-mode)))
    (chaplet-mode -1)))

(ert-deftest chaplet-test-entry-face-setup-on-load ()
  "Loading chaplet.el calls `chaplet-face-setup' exactly once.
`chaplet.el' is re-evaluated with the setup function stubbed; the
load-time call must hit the stub.  Requires short-circuit because all
dependency features are already loaded, so only the top-level setup
call executes."
  :tags '(:chaplet)
  (let ((calls 0))
    (cl-letf (((symbol-function 'chaplet-face-setup)
               (lambda () (setq calls (1+ calls)))))
      (load (expand-file-name "chaplet.el" chaplet-test--root)
            nil :nomessage)
      (should (= calls 1)))))

;;; Integration: full-loop + cross-module smoke (tag chaplet)

(defvar chaplet-test--fake-bd-state
  (expand-file-name "test/.fake-bd-state" chaplet-test--root)
  "State file used by fake-bd in stateful (full-loop) mode.")

(defun chaplet-test--fresh-state ()
  "Remove any stale fake-bd state file."
  (ignore-errors (delete-file chaplet-test--fake-bd-state)))

(defun chaplet-test--with-state (body)
  "Run BODY with fake-bd stateful mode active (fresh state, cleaned after)."
  (chaplet-test--fresh-state)
  (unwind-protect
      (let ((process-environment
             (cons (concat "CHAPLET_FAKE_BD_STATE=" chaplet-test--fake-bd-state)
                   process-environment))
            (chaplet-bd-program chaplet-test--fake-bd))
        (funcall body))
    (chaplet-test--fresh-state)))

(ert-deftest chaplet-test-full-loop-approve ()
  "Full loop: staged inbox bead → approve (undefer) → removed from inbox."
  :tags '(:chaplet)
  (chaplet-test--with-state
   (lambda ()
     ;; Inbox (staged) shows bd-2.
     (let ((beads (chaplet-list--fetch 'inbox)))
       (should (= (length beads) 1))
       (should (equal (alist-get 'id (car beads)) "bd-2"))
       (should (equal (alist-get 'status (car beads)) "deferred")))
     ;; Approve it (undefer + refresh).
     (cl-letf (((symbol-function 'chaplet-transient--refresh)
                (lambda () nil)))
       (chaplet-approve "bd-2"))
     ;; Re-fetch: gone from the staged inbox.
     (should (null (chaplet-list--fetch 'inbox))))))

(ert-deftest chaplet-test-full-loop-reject ()
  "Full loop: reject comments \"rejected: <fb>\" and keeps the bead staged."
  :tags '(:chaplet)
  (chaplet-test--with-state
   (lambda ()
     (cl-letf (((symbol-function 'read-string)
                (lambda (&rest _) "needs work"))
               ((symbol-function 'chaplet-transient--refresh)
                (lambda () nil)))
       (chaplet-reject "bd-2"))
     ;; Bead stays staged in the inbox.
     (let ((after (chaplet-list--fetch 'inbox)))
       (should (= (length after) 1))
       (should (equal (alist-get 'id (car after)) "bd-2")))
     ;; Comment recorded with the "rejected: <fb>" prefix.
     (should (file-exists-p chaplet-test--fake-bd-state))
     (should (with-temp-buffer
               (insert-file-contents chaplet-test--fake-bd-state)
               (string-match-p "rejected: needs work" (buffer-string)))))))

(ert-deftest chaplet-test-smoke-entry ()
  "Cross-module smoke: `chaplet` opens the inbox list; transient reachable."
  :tags '(:chaplet)
  (let ((chaplet-bd-program chaplet-test--fake-bd))
    (chaplet)
    (unwind-protect
        (progn
          (should (eq major-mode 'chaplet-list-mode))
          (should (equal (buffer-name) "*chaplet*"))
          (should (eq chaplet-list--current-view 'inbox))
          (should (fboundp 'chaplet-transient))
          (should (eq (lookup-key chaplet-list-mode-map (kbd "?"))
                      'chaplet-transient)))
      (kill-buffer "*chaplet*"))))

(ert-deftest chaplet-test-graph-headless-render ()
  "`chaplet-graph--render' uses the text fallback when display-images-p is nil."
  :tags '(:chaplet)
  (cl-letf (((symbol-function 'display-images-p) (lambda () nil)))
    (with-temp-buffer
      (let* ((f (chaplet-test--graph-fixture))
             (buf (chaplet-graph--render (car f) (cdr f) nil)))
        (should (eq buf (current-buffer)))
        (should chaplet-graph--text-mode)
        (should (string-match-p "bd-1" (buffer-string)))))))

(ert-deftest chaplet-test-graph-headless-fallback ()
  "`chaplet-graph' renders a navigable text outline in headless sessions."
  :tags '(:chaplet)
  (let ((chaplet-bd-program chaplet-test--fake-bd))
    (chaplet-graph)
    (should (get-buffer "*chaplet:graph*"))
    (should (with-current-buffer "*chaplet:graph*"
              (and chaplet-graph--text-mode
                   (string-match-p "bd-1" (buffer-string))
                   (string-match-p "bd-2" (buffer-string)))))
    (kill-buffer "*chaplet:graph*")))

(ert-deftest chaplet-test-list-v-key ()
  "`v' in `chaplet-list-mode-map' switches views."
  :tags '(:chaplet)
  (should (eq (lookup-key chaplet-list-mode-map (kbd "v"))
              'chaplet-list-set-view)))

(ert-deftest chaplet-test-list-set-view-closed ()
  "`chaplet-list-set-view' to `closed` renders closed beads in-place.
Uses the single shared `*chaplet*` buffer (no per-view buffers)."
  :tags '(:chaplet)
  (cl-letf (((symbol-function 'chaplet-bd-query)
             (lambda (_q) '(((id . "bd-9") (status . "closed")
                             (issue_type . "task") (title . "done"))))))
    (unwind-protect
        (progn
          (chaplet-list-set-view 'inbox)
          (should (get-buffer "*chaplet*"))
          (chaplet-list-set-view 'closed)
          (should (eq chaplet-list--current-view 'closed))
          (should (get-buffer "*chaplet*"))
          (should-not (get-buffer "*chaplet:closed*"))
          (should (with-current-buffer "*chaplet*"
                    (string-match-p "bd-9" (buffer-string)))))
      (kill-buffer "*chaplet*"))))

(ert-deftest chaplet-test-bd-graph-dot-args ()
  "`chaplet-bd-graph-dot' assembles graph/list args per filters."
  :tags '(:chaplet)
  (let ((captured nil))
    (cl-letf (((symbol-function 'chaplet-bd--invoke)
               (lambda (args) (setq captured args) (cons 0 "digraph {}"))))
      (chaplet-bd-graph-dot nil)
      (should (equal captured '("graph" "--dot" "--all")))
      (chaplet-bd-graph-dot '((:closed . t)))
      (should (equal captured '("list" "--format" "dot" "--all")))
      (chaplet-bd-graph-dot '((:id . "bd-9")))
      (should (equal captured '("graph" "--dot" "bd-9"))))))

(ert-deftest chaplet-test-bd-graph-data-filters ()
  "`chaplet-bd-graph-data' without filters calls `chaplet-bd-list' with nil filters."
  (let ((captured :unset))
    (cl-letf (((symbol-function 'chaplet-bd-list)
               (lambda (filters) (setq captured filters) nil)))
      (chaplet-bd-graph-data)
      (should (equal captured nil)))))

(ert-deftest chaplet-test-bd-graph-data-all ()
  "`chaplet-bd-graph-data' forwards its filters alist to `chaplet-bd-list'."
  (let ((captured :unset))
    (cl-letf (((symbol-function 'chaplet-bd-list)
               (lambda (filters) (setq captured filters) nil)))
      (chaplet-bd-graph-data '((:all . t)))
      (should (equal captured '((:all . t)))))))

(ert-deftest chaplet-test-bd-graph-data-deps ()
  "`chaplet-bd-graph-data' bead alists carry the `dependencies' field."
  (let ((chaplet-bd-program chaplet-test--fake-bd))
    (let ((beads (chaplet-bd-graph-data)))
      (should (= (length beads) 2))
      (should (equal (alist-get 'dependencies (car beads)) nil))
      (should (equal (alist-get 'dependencies (cadr beads)) '("bd-1"))))))

(ert-deftest chaplet-test-bd-normalize-deps ()
  "`chaplet-bd--normalize' maps dependency objects to `depends_on_id' strings."
  (should (equal (chaplet-bd--normalize-deps
                  '(((issue_id . "bd-2") (depends_on_id . "bd-1") (type . "blocks"))
                    ((issue_id . "bd-2") (depends_on_id . "bd-0") (type . "parent-child"))))
                 '("bd-1" "bd-0")))
  (should (equal (chaplet-bd--normalize-deps '("bd-1")) '("bd-1")))
  (should (equal (chaplet-bd--normalize-deps nil) nil))
  (let ((bead (chaplet-bd--normalize
               '((id . "bd-2")
                 (dependencies . (((issue_id . "bd-2") (depends_on_id . "bd-1"))))))))
    (should (equal (alist-get 'dependencies bead) '("bd-1")))))

(ert-deftest chaplet-test-graph-include-closed ()
  "`chaplet-graph' defaults to the all view; C-u opens the open view."
  :tags '(:chaplet)
  (let ((captured :unset))
    (cl-letf (((symbol-function 'chaplet-bd-graph-data)
               (lambda (filters) (setq captured filters) nil)))
      (chaplet-graph)                       ; no prefix: all view
      (should (equal captured '((:all . t)))))
    (kill-buffer "*chaplet:graph*")
    (setq captured :unset)
    (cl-letf (((symbol-function 'chaplet-bd-graph-data)
               (lambda (filters) (setq captured filters) nil)))
      (let ((current-prefix-arg '(4)))
        (call-interactively #'chaplet-graph)) ; C-u prefix arg: open view
      (should (equal captured '((:status . "open")))))
    (kill-buffer "*chaplet:graph*")))

(ert-deftest chaplet-test-list-s-key ()
  "`s' in `chaplet-list-mode-map' opens the graph for the current view."
  :tags '(:chaplet)
  (should (eq (lookup-key chaplet-list-mode-map (kbd "s"))
              'chaplet-list-graph)))

(ert-deftest chaplet-test-list-graph ()
  "`chaplet-list-graph' passes `chaplet-list--current-view' to `chaplet-graph'."
  :tags '(:chaplet)
  (let ((called :unset))
    (cl-letf (((symbol-function 'chaplet-graph)
               (lambda (view) (setq called view))))
      (with-temp-buffer
        (setq-local chaplet-list--current-view 'closed)
        (chaplet-list-graph)
        (should (eq called 'closed))))))

(ert-deftest chaplet-test-list-bind-keys ()
  "RET/v/s/q bound in `chaplet-list-mode-map' (plain + evil-aware)."
  :tags '(:chaplet)
  (should (eq (lookup-key chaplet-list-mode-map (kbd "RET")) 'chaplet-list-open))
  (should (eq (lookup-key chaplet-list-mode-map (kbd "v")) 'chaplet-list-set-view))
  (should (eq (lookup-key chaplet-list-mode-map (kbd "s")) 'chaplet-list-graph))
  (should (eq (lookup-key chaplet-list-mode-map (kbd "q")) 'quit-window)))

(ert-deftest chaplet-test-list-bind-question ()
  "`?' bound via the evil-aware helper in `chaplet-list-mode-map'."
  :tags '(:chaplet)
  (should (eq (lookup-key chaplet-list-mode-map (kbd "?")) 'chaplet-transient)))

(ert-deftest chaplet-test-list-bind-evil ()
  "`chaplet-list--bind' also binds in evil normal + motion states."
  :tags '(:chaplet)
  (let (called)
    (cl-letf (((symbol-function 'featurep) (lambda (f) (eq f 'evil)))
              ((symbol-function 'evil-define-key*)
               (lambda (state _map _key _cmd) (push state called))))
      (chaplet-list--bind (kbd "x") #'ignore))
    (should (= (length called) 2))
    (should (memq 'normal called))
    (should (memq 'motion called))))

(ert-deftest chaplet-test-graph-refresh-closed ()
  "`chaplet-graph--refresh' forwards view filters to `chaplet-bd-graph-data'."
  :tags '(:chaplet)
  (let (captured)
    (with-temp-buffer
      (setq-local chaplet-graph--view 'all)
      (cl-letf (((symbol-function 'chaplet-bd-graph-data)
                 (lambda (filters) (setq captured filters) nil)))
        (chaplet-graph--refresh)
        (should (equal captured '((:all . t))))))
    (setq captured :unset)
    (with-temp-buffer
      (setq-local chaplet-graph--view 'closed)
      (cl-letf (((symbol-function 'chaplet-bd-graph-data)
                 (lambda (filters) (setq captured filters) nil)))
        (chaplet-graph--refresh)
        (should (equal captured '((:status . "closed"))))))))

(ert-deftest chaplet-test-graph-set-view ()
  "`chaplet-graph-set-view' switches the view symbol and refreshes."
  :tags '(:chaplet)
  (let (captured)
    (with-temp-buffer
      (setq-local chaplet-graph--view 'all)
      (cl-letf (((symbol-function 'chaplet-bd-graph-data)
                 (lambda (filters) (setq captured filters) nil)))
        (chaplet-graph-set-view 'closed)
        (should (eq chaplet-graph--view 'closed))
        (should (equal captured '((:status . "closed"))))))))

(ert-deftest chaplet-test-graph-set-view-interactive ()
  "`chaplet-graph-set-view' completes over `chaplet-bd--view-names'."
  :tags '(:chaplet)
  (let (prompt-collection)
    (cl-letf (((symbol-function 'completing-read)
               (lambda (_prompt collection &rest _)
                 (setq prompt-collection collection)
                 "in-progress"))
              ((symbol-function 'chaplet-bd-graph-data)
               (lambda (_filters) nil)))
      (with-temp-buffer
        (setq-local chaplet-graph--view 'all)
        (call-interactively #'chaplet-graph-set-view)
        (should (equal prompt-collection
                       '("inbox" "open" "in-progress" "blocked" "closed" "all")))
        (should (eq chaplet-graph--view 'in-progress))))))

(ert-deftest chaplet-test-graph-default-view ()
  "`chaplet-graph--view' defaults to `all' in a fresh buffer."
  (with-temp-buffer
    (should (eq chaplet-graph--view 'all))))

(ert-deftest chaplet-test-graph-mode-map ()
  "`chaplet-graph-mode-map' binds the full navigation key set."
  :tags '(:chaplet)
  (should (eq (lookup-key chaplet-graph-mode-map (kbd "n"))
              'chaplet-graph--focus-next))
  (should (eq (lookup-key chaplet-graph-mode-map (kbd "p"))
              'chaplet-graph--focus-prev))
  (should (eq (lookup-key chaplet-graph-mode-map (kbd "RET"))
              'chaplet-graph--open-focused))
  (should (eq (lookup-key chaplet-graph-mode-map (kbd "d"))
              'chaplet-graph--jump-dependents))
  (should (eq (lookup-key chaplet-graph-mode-map (kbd "f"))
              'chaplet-graph--jump-deps))
  (should (eq (lookup-key chaplet-graph-mode-map (kbd "g"))
              'chaplet-graph--refresh))
  (should (eq (lookup-key chaplet-graph-mode-map (kbd "v"))
              'chaplet-graph-set-view))
  (should-not (lookup-key chaplet-graph-mode-map (kbd "c")))
  (should (eq (lookup-key chaplet-graph-mode-map (kbd "q")) 'quit-window)))

(ert-deftest chaplet-test-graph-bind-evil ()
  "`chaplet-graph--bind' also binds in evil normal + motion states."
  :tags '(:chaplet)
  (let (called)
    (cl-letf (((symbol-function 'featurep) (lambda (f) (eq f 'evil)))
              ((symbol-function 'evil-define-key*)
               (lambda (state _map _key _cmd) (push state called))))
      (chaplet-graph--bind (kbd "x") #'ignore))
    (should (= (length called) 2))
    (should (memq 'normal called))
    (should (memq 'motion called))))

(ert-deftest chaplet-test-graph-major-mode ()
  "`chaplet-graph' leaves a read-only `chaplet-graph-mode' buffer, no cursor."
  :tags '(:chaplet)
  (let ((chaplet-bd-program chaplet-test--fake-bd))
    (chaplet-graph)
    (unwind-protect
        (with-current-buffer "*chaplet:graph*"
          (should (derived-mode-p 'chaplet-graph-mode))
          (should (eq major-mode 'chaplet-graph-mode))
          (should buffer-read-only)
          (should-not cursor-type))
      (kill-buffer "*chaplet:graph*"))))

(ert-deftest chaplet-test-graph-no-image-mode ()
  "`chaplet-graph--render' never calls `image-mode' in image or text path."
  :tags '(:chaplet)
  (cl-letf (((symbol-function 'image-mode)
             (lambda (&rest _) (error "image-mode must not be called"))))
    ;; Text path: images unavailable.
    (cl-letf (((symbol-function 'display-images-p) (lambda () nil)))
      (with-temp-buffer
        (let ((f (chaplet-test--graph-fixture)))
          (chaplet-graph--render (car f) (cdr f) nil)
          (should chaplet-graph--text-mode))))
    ;; Image path: svg available (svg-image stubbed to a valid image).
    (cl-letf (((symbol-function 'display-images-p) (lambda () t))
              ((symbol-function 'svg-image)
               (lambda (&rest _)
                 (list 'image :type 'svg :data "<svg/>"))))
      (with-temp-buffer
        (let ((f (chaplet-test--graph-fixture)))
          (chaplet-graph--render (car f) (cdr f) nil)
          (should-not chaplet-graph--text-mode)
          (should (eq (lookup-key chaplet-graph-mode-map [bd-1 mouse-1])
                      'chaplet-graph--open-node)))))))

;;; chaplet-face tests

(defun chaplet-test-face--stub-bg (bg)
  "Return a `face-attribute' stub reporting DEFAULT background BG."
  (lambda (face attr &optional _frame _inherit)
    (if (and (eq face 'default) (eq attr :background))
        bg
      (face-attribute face attr nil 'default))))

(ert-deftest chaplet-test-face-dark-p-dark ()
  "`chaplet-face-dark-p' is non-nil for dark default backgrounds."
  (cl-letf (((symbol-function 'face-attribute)
             (chaplet-test-face--stub-bg "#282c34")))
    (should (chaplet-face-dark-p))))

(ert-deftest chaplet-test-face-dark-p-light ()
  "`chaplet-face-dark-p' is nil for light default backgrounds."
  (cl-letf (((symbol-function 'face-attribute)
             (chaplet-test-face--stub-bg "#ffffff")))
    (should-not (chaplet-face-dark-p))))

(ert-deftest chaplet-test-face-adapt-respecs ()
  "`chaplet-face-adapt' re-specs every palette face once; idempotent."
  (let ((specs nil))
    (cl-letf (((symbol-function 'face-attribute)
               (chaplet-test-face--stub-bg "#ffffff"))
              ((symbol-function 'face-spec-set)
               (lambda (face spec &optional type)
                 (push (list face spec type) specs))))
      (chaplet-face-adapt)
      (let ((first (length specs)))
        (should (= first (length chaplet-face--dark-palette)))
        (should (= first (length chaplet-face--light-palette)))
        (dolist (e chaplet-face--dark-palette)
          (should (assq (car e) specs)))
        ;; Idempotent: a second call re-specs again, but never errors.
        (chaplet-face-adapt)
        (should (= (length specs) (* 2 first)))))))

(ert-deftest chaplet-test-face-state-face-mapping ()
  "`chaplet-state-face' maps each status to its face symbol."
  (should (eq (chaplet-state-face "deferred") 'chaplet-state-deferred))
  (should (eq (chaplet-state-face "in_progress") 'chaplet-state-in-progress))
  (should (eq (chaplet-state-face "blocked") 'chaplet-state-blocked))
  (should (eq (chaplet-state-face "closed") 'chaplet-state-closed))
  (should (eq (chaplet-state-face "open") 'chaplet-state-open))
  (should-not (chaplet-state-face "unknown"))
  (should-not (chaplet-state-face nil)))

(ert-deftest chaplet-test-face-state-color ()
  "`chaplet-state-color' mirrors the effective foreground attribute."
  (cl-letf (((symbol-function 'face-attribute)
             (lambda (face attr &optional _frame _inherit)
               (if (and (eq face 'chaplet-state-deferred)
                        (eq attr :foreground))
                   "#abcdef"
                 (face-attribute face attr nil 'default)))))
    (should (equal (chaplet-state-color "deferred") "#abcdef"))))

(ert-deftest chaplet-test-face-state-color-fallback ()
  "`chaplet-state-color' falls back to the dark palette when face unset."
  (cl-letf (((symbol-function 'face-attribute) (lambda (&rest _) nil)))
    (should (equal (chaplet-state-color "deferred") "#d19a66"))
    (should-not (chaplet-state-color "unknown"))))

(ert-deftest chaplet-test-face-priority-face ()
  "`chaplet-priority-face' maps priority values to faces."
  (should (eq (chaplet-priority-face 2) 'chaplet-priority-high))
  (should (eq (chaplet-priority-face 1) 'chaplet-priority-medium))
  (should (eq (chaplet-priority-face 0) 'chaplet-priority-low))
  (should (eq (chaplet-priority-face "2") 'chaplet-priority-high))
  (should-not (chaplet-priority-face nil))
  (should-not (chaplet-priority-face 5)))

(ert-deftest chaplet-test-face-type-face ()
  "`chaplet-type-face' maps issue types to faces."
  (should (eq (chaplet-type-face "task") 'chaplet-type-task))
  (should (eq (chaplet-type-face "epic") 'chaplet-type-epic))
  (should (eq (chaplet-type-face "bug") 'chaplet-type-bug))
  (should-not (chaplet-type-face "feature"))
  (should-not (chaplet-type-face nil)))

(ert-deftest chaplet-test-face-setup-hook ()
  "`chaplet-face-setup' adapts and registers the theme hook exactly once."
  (let ((adapted 0))
    (unwind-protect
        (progn
          (cl-letf (((symbol-function 'face-attribute)
                     (chaplet-test-face--stub-bg "#282c34"))
                    ((symbol-function 'face-spec-set)
                     (lambda (&rest _) (setq adapted (1+ adapted)))))
            (chaplet-face-setup)
            (let ((calls (length (memq 'chaplet-face-adapt after-load-theme-hook))))
              (should (= calls 1))
              (chaplet-face-setup)
              (should (= (length (memq 'chaplet-face-adapt after-load-theme-hook))
                         calls))
              (should (= adapted (* 2 (length chaplet-face--dark-palette)))))))
      (remove-hook 'after-load-theme-hook #'chaplet-face-adapt))))

(ert-deftest chaplet-test-face-deffaces ()
  "All chaplet faces are defined."
  (dolist (face '(chaplet-state-deferred chaplet-state-in-progress
                  chaplet-state-blocked chaplet-state-closed
                  chaplet-state-open
                  chaplet-priority-high chaplet-priority-medium
                  chaplet-priority-low
                  chaplet-type-epic chaplet-type-task chaplet-type-bug
                  chaplet-header chaplet-staged chaplet-id chaplet-bar))
    (should (facep face))))

;;; chaplet-graph pure layout + SVG pipeline tests (design §7.4)

(defvar chaplet-test--graph-beads
  '(((id . "bd-1") (title . "one") (status . "open") (priority . 2)
     (issue_type . "task") (dependencies . nil))
    ((id . "bd-2") (title . "two") (status . "deferred") (priority . 1)
     (issue_type . "bug") (dependencies . ("bd-1")))
    ((id . "bd-3") (title . "three") (status . "blocked") (priority . 0)
     (issue_type . "epic") (dependencies . ("bd-2" "missing-dep"))))
  "Fake bead alists for graph pipeline tests (one unknown dep).")

(defun chaplet-test--graph-fixture ()
  "Return (LAYOUT-NODES . EDGES) from `chaplet-test--graph-beads'."
  (chaplet-graph--layout
   (chaplet-graph--nodes chaplet-test--graph-beads)))

(ert-deftest chaplet-test-graph-nodes ()
  "`chaplet-graph--nodes' maps bead alists to node plists."
  (let ((nodes (chaplet-graph--nodes
                (list (car chaplet-test--graph-beads)))))
    (should (= (length nodes) 1))
    (let ((n (car nodes)))
      (should (equal (plist-get n :id) "bd-1"))
      (should (equal (plist-get n :title) "one"))
      (should (equal (plist-get n :state) "open"))
      (should (equal (plist-get n :type) "task"))
      (should (equal (plist-get n :priority) 2))
      (should (equal (plist-get n :deps) nil)))))

(ert-deftest chaplet-test-graph-title-truncation ()
  "Titles longer than `chaplet-graph--title-max' are truncated."
  (let ((long (make-string 60 ?x)))
    (let ((title (plist-get (car (chaplet-graph--nodes
                                  (list (list (cons 'id "bd-9")
                                              (cons 'title long)))))
                            :title)))
      (should (<= (string-width title) chaplet-graph--title-max))
      (should (string-suffix-p "…" title)))
    ;; Short titles pass through unchanged.
    (let ((title (plist-get (car (chaplet-graph--nodes
                                  (list (list (cons 'id "bd-9")
                                              (cons 'title "ok")))))
                            :title)))
      (should (equal title "ok")))))

(ert-deftest chaplet-test-graph-layout-layers ()
  "`chaplet-graph--layout' orders nodes by longest-path layer."
  (let* ((fixture (chaplet-test--graph-fixture))
         (nodes (car fixture))
         (by-id (mapcar (lambda (n) (cons (plist-get n :id) n)) nodes)))
    (let ((y-bd-1 (plist-get (cdr (assoc "bd-1" by-id)) :y))
          (y-bd-2 (plist-get (cdr (assoc "bd-2" by-id)) :y))
          (y-bd-3 (plist-get (cdr (assoc "bd-3" by-id)) :y))
          (y-ghost (plist-get (cdr (assoc "missing-dep" by-id)) :y)))
      (should (< y-bd-1 y-bd-2 y-bd-3))
      ;; Ghost deps sit at the root layer (depth 0).
      (should (= y-bd-1 y-ghost))
      ;; y = layer * (h + y-gap) + margin.
      (should (= y-bd-1 chaplet-graph--margin))
      (should (= y-bd-2 (+ chaplet-graph--margin
                           chaplet-graph--node-h chaplet-graph--y-gap)))
      (should (= y-bd-3 (+ y-bd-2 chaplet-graph--node-h
                           chaplet-graph--y-gap))))))

(ert-deftest chaplet-test-graph-layout-non-overlap ()
  "Nodes in the same layer do not overlap horizontally."
  (let* ((fixture (chaplet-test--graph-fixture))
         (nodes (car fixture))
         (rows (make-hash-table :test 'eql)))
    (dolist (n nodes)
      (push n (gethash (plist-get n :y) rows)))
    (maphash
     (lambda (_y row)
       (let ((sorted (sort (copy-sequence row)
                           (lambda (a b) (< (plist-get a :x) (plist-get b :x))))))
         (let ((prev nil))
           (dolist (n sorted)
             (when prev
               (should (<= (+ (plist-get prev :x) (plist-get prev :w))
                           (plist-get n :x))))
             (setq prev n)))))
     rows)
    ;; Minimum width and height per node.
    (dolist (n nodes)
      (should (>= (plist-get n :w) 90))
      (should (= (plist-get n :h) chaplet-graph--node-h)))))

(ert-deftest chaplet-test-graph-layout-ghost ()
  "Unknown deps become ghost nodes with closed styling and an edge."
  (let* ((fixture (chaplet-test--graph-fixture))
         (nodes (car fixture))
         (edges (cdr fixture))
         (ghost (cl-find-if (lambda (n) (plist-get n :ghost)) nodes)))
    (should ghost)
    (should (equal (plist-get ghost :id) "missing-dep"))
    (should (equal (plist-get ghost :state) "closed"))
    (should (string-match-p "(closed)" (plist-get ghost :title)))
    (should (member '("bd-3" . "missing-dep") edges))
    (should (member '("bd-2" . "bd-1") edges))
    (should (= (length nodes) 4))))

(ert-deftest chaplet-test-graph-layout-deterministic ()
  "`chaplet-graph--layout' returns identical results across calls."
  (let ((a (chaplet-test--graph-fixture))
        (b (chaplet-test--graph-fixture)))
    (should (equal (car a) (car b)))
    (should (equal (cdr a) (cdr b))))
  ;; Empty input → empty layout, no error.
  (should (equal (chaplet-graph--layout nil) '(nil . nil))))

;; Reference oracle: the previous while-changed relaxation, kept so the
;; new single-pass Kahn `chaplet-graph--layers' can be proven equivalent.
(defun chaplet-test--layers-relaxation (nodes)
  "Return hash table ID → layer for NODES via while-changed relaxation.
Mirrors the pre-longest-path implementation of `chaplet-graph--layers'."
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

(defun chaplet-test--layers-equal-p (a b)
  "Return t when layer hash tables A and B assign the same layer.
A missing key means layer 0 in both (the old relaxation never stored
layer-0 roots; consumers read layers with `(gethash id layer 0)')."
  (let ((ok t))
    (maphash (lambda (id l)
               (unless (equal l (gethash id b 0))
                 (setq ok nil)))
             a)
    (maphash (lambda (id l)
               (unless (equal l (gethash id a 0))
                 (setq ok nil)))
             b)
    ok))

(defun chaplet-test--dag-nodes (spec)
  "Convert SPEC (alist id → deps) into graph node plists.
Each entry is (ID . DEPS); ids may be strings or symbols, and are
normalized to strings (matching `chaplet-graph--node' output).
Nodes carry :deps only — enough for `chaplet-graph--layers'."
  (let ((str (lambda (x) (if (stringp x) x (symbol-name x)))))
    (mapcar (lambda (entry)
              (let ((id (funcall str (car entry))))
                (list :id id
                      :title id
                      :state "open"
                      :type nil
                      :priority nil
                      :deps (mapcar str (cdr entry)))))
            spec)))

(ert-deftest chaplet-test-graph-layers-equivalence ()
  "New Kahn `chaplet-graph--layers' matches old relaxation on fixtures."
  (dolist (nodes
           (list
            ;; Existing graph fixture (with and without ghosts).
            (chaplet-graph--nodes chaplet-test--graph-beads)
            (chaplet-graph--add-ghosts
             (chaplet-graph--nodes chaplet-test--graph-beads))
            ;; Diamond DAG.
            (chaplet-test--dag-nodes
             '((a) (b . (a)) (c . (a)) (d . (b c)) (e . (d))
               (f . (d)) (g . (e f)) (h . (g))))
            ;; Layered DAG with a shared sink and a missing dep.
            (chaplet-test--dag-nodes
             '((a) (b . (a)) (c . (b)) (d . (a)) (e . (d c))
               (f . (e)) (g . (f missing))))))
    (should (chaplet-test--layers-equal-p
             (chaplet-graph--layers nodes)
             (chaplet-test--layers-relaxation nodes)))))

(ert-deftest chaplet-test-graph-layers-perf-500 ()
  "500-node chain DAG layers compute in a single pass, well under a second."
  (let ((nodes (chaplet-test--dag-nodes
                (append (list (cons "n0" nil))
                        (cl-loop for i from 1 to 499
                                 collect (cons (format "n%d" i)
                                               (list (format "n%d" (1- i)))))))))
    (let ((t0 (float-time)))
      (let ((layers (chaplet-graph--layers nodes)))
        (should (< (- (float-time) t0) 1.0))
        ;; Longest-path invariant: node i sits exactly at layer i.
        (cl-loop for i from 0 to 499
                 do (should (= (gethash (format "n%d" i) layers) i)))))))

(ert-deftest chaplet-test-graph-layers-cycle-safe ()
  "`chaplet-graph--layers' terminates on cycles and stays deterministic."
  (let* ((nodes (chaplet-test--dag-nodes
                 '((a . (b)) (b . (a)) (r) (c . (r)) (d . (c)))))
         (l1 (chaplet-graph--layers nodes))
         (l2 (chaplet-graph--layers nodes)))
    ;; Total: every node gets an integer layer (no hang).
    (dolist (id '("a" "b" "r" "c" "d"))
      (should (integerp (gethash id l1 0))))
    ;; Deterministic across calls.
    (should (chaplet-test--layers-equal-p l1 l2))
    ;; Acyclic nodes keep longest-path semantics around the cycle.
    (should (= (gethash "r" l1 0)))
    (should (= (gethash "c" l1) 1))
    (should (= (gethash "d" l1) 2))))

(ert-deftest chaplet-test-graph-svg-elements ()
  "`chaplet-graph--svg' emits nodes, edges (arrows) and optional halo."
  (let* ((fixture (chaplet-test--graph-fixture))
         (nodes (car fixture))
         (edges (cdr fixture))
         (svg (chaplet-graph--svg nodes edges nil))
         (rects (dom-by-tag svg 'rect))
         (texts (dom-by-tag svg 'text))
         (lines (dom-by-tag svg 'line))
         (polys (dom-by-tag svg 'polygon)))
    (should (= (length rects) (length nodes)))      ; one rect per node
    (should (= (length texts) (* 2 (length nodes)))) ; id + title
    (should (= (length lines) (length edges)))       ; one line per edge
    (should (= (length polys) (length edges)))       ; one arrowhead per edge
    (should (seq-some (lambda (r)
                        (equal (dom-attr r 'id) "node-bd-1"))
                      rects))
    (should (seq-some (lambda (r)
                        (equal (dom-attr r 'fill)
                               (chaplet-state-color "open")))
                      rects))))

(ert-deftest chaplet-test-graph-svg-halo ()
  "Focus halo rect appears iff FOCUS-ID matches a node."
  (let* ((fixture (chaplet-test--graph-fixture))
         (nodes (car fixture))
         (edges (cdr fixture))
         (svg (chaplet-graph--svg nodes edges "bd-2"))
         (halos (cl-remove-if-not
                 (lambda (r) (equal (dom-attr r 'stroke-width) 3))
                 (dom-by-tag svg 'rect))))
    (should (= (length halos) 1))
    (let ((svg-no (chaplet-graph--svg nodes edges nil)))
      (should-not (cl-remove-if-not
                   (lambda (r) (equal (dom-attr r 'stroke-width) 3))
                   (dom-by-tag svg-no 'rect))))))

(ert-deftest chaplet-test-graph-svg-string ()
  "`chaplet-graph--svg-string' renders XML containing ids and arrows."
  (let* ((fixture (chaplet-test--graph-fixture))
         (s (chaplet-graph--svg-string
             (chaplet-graph--svg (car fixture) (cdr fixture) nil))))
    (should (string-match-p "<svg" s))
    (should (string-match-p "node-bd-1" s))
    (should (string-match-p "polygon" s))))

(ert-deftest chaplet-test-graph-image-map ()
  "`chaplet-graph--image-map' builds one rect region per node."
  (let* ((fixture (chaplet-test--graph-fixture))
         (nodes (car fixture))
         (map (chaplet-graph--image-map nodes))
         (by-id (make-hash-table :test 'equal)))
    (dolist (n nodes)
      (puthash (plist-get n :id) n by-id))
    (should (= (length map) (length nodes)))
    (dolist (region map)
      (let* ((area (car region))
             (id (cadr region))
             (plist (caddr region))
             (node (gethash (symbol-name id) by-id))
             (coords (cdr area)))
        (should (eq (car area) 'rect))
        (should node)
        (should (equal (caar coords) (plist-get node :x)))
        (should (equal (cdar coords) (plist-get node :y)))
        (should (equal (cadr coords) (+ (plist-get node :x) (plist-get node :w))))
        (should (equal (cddr coords) (+ (plist-get node :y) (plist-get node :h))))
        (should (plist-get plist 'help-echo))
        (should (string-match-p (regexp-quote (plist-get node :title))
                                (plist-get plist 'help-echo)))))))

(ert-deftest chaplet-test-graph-image-map-event ()
  "Region ids compose `[ID mouse-1]' / `[ID mouse-2]' events for dispatch."
  (let* ((fixture (chaplet-test--graph-fixture))
         (map (chaplet-graph--image-map (car fixture)))
         (km (make-sparse-keymap)))
    (define-key km [bd-1 mouse-1] #'ignore)
    (define-key km [bd-1 mouse-2] #'ignore)
    (should (eq (car (car (car map))) 'rect))
    (should (eq (lookup-key km [bd-1 mouse-1]) #'ignore))
    (should (eq (lookup-key km [bd-1 mouse-2]) #'ignore))))

;;; chaplet-graph buffer + navigation tests (design §7.4, uvy.5)

(ert-deftest chaplet-test-graph-focus-cycle ()
  "`chaplet-graph--focus-next'/'--focus-prev' cycle focus via `chaplet-graph--focus-set'."
  (let ((rendered nil))
    (cl-letf (((symbol-function 'chaplet-graph--focus-set)
               (lambda (focus)
                 ;; Real `chaplet-graph--focus-set' updates the buffer var
                 ;; too; the spy must mirror that or position tracking in
                 ;; `chaplet-graph--focus-relative' loses the focus.
                 (setq rendered focus)
                 (setq-local chaplet-graph--focus-id focus))))
      (with-temp-buffer
        (let* ((f (chaplet-test--graph-fixture))
               (ids (mapcar (lambda (n) (plist-get n :id)) (car f))))
          (setq-local chaplet-graph--nodes (car f))
          (setq-local chaplet-graph--edges (cdr f))
          (setq-local chaplet-graph--focus-id nil)
          ;; No focus yet → n takes the first node in layout order.
          (chaplet-graph--focus-next)
          (should (equal chaplet-graph--focus-id (car ids)))
          (should (equal rendered (car ids)))
          ;; Forward step.
          (chaplet-graph--focus-next)
          (should (equal chaplet-graph--focus-id (cadr ids)))
          ;; Wrap from last to first.
          (setq-local chaplet-graph--focus-id (car (last ids)))
          (chaplet-graph--focus-next)
          (should (equal chaplet-graph--focus-id (car ids)))
          ;; p wraps backward.
          (chaplet-graph--focus-prev)
          (should (equal chaplet-graph--focus-id (car (last ids)))))))))

(ert-deftest chaplet-test-graph-open-focused ()
  "`chaplet-graph--open-focused' opens the focused id in `chaplet-detail'."
  (let ((opened nil))
    (cl-letf (((symbol-function 'chaplet-detail)
               (lambda (id) (setq opened id))))
      (with-temp-buffer
        (setq-local chaplet-graph--focus-id "bd-2")
        (chaplet-graph--open-focused)
        (should (equal opened "bd-2"))))
    ;; No focus → message, no detail call.
    (let ((opened :unset))
      (cl-letf (((symbol-function 'chaplet-detail)
                 (lambda (id) (setq opened id))))
        (with-temp-buffer
          (setq-local chaplet-graph--focus-id nil)
          (chaplet-graph--open-focused)
          (should (eq opened :unset)))))))

(ert-deftest chaplet-test-graph-jump ()
  "`chaplet-graph--jump-deps'/'--jump-dependents' move focus along edges."
  (let ((rendered nil))
    (cl-letf (((symbol-function 'chaplet-graph--focus-set)
               (lambda (focus)
                 ;; Mirror the real focus-set's buffer-var update (see
                 ;; `chaplet-test-graph-focus-cycle').
                 (setq rendered focus)
                 (setq-local chaplet-graph--focus-id focus))))
      (with-temp-buffer
        (let ((f (chaplet-test--graph-fixture)))
          (setq-local chaplet-graph--nodes (car f))
          (setq-local chaplet-graph--edges (cdr f))
          (setq-local chaplet-graph--focus-id "bd-2")
          ;; f: bd-2 depends on bd-1.
          (chaplet-graph--jump-deps)
          (should (equal chaplet-graph--focus-id "bd-1"))
          (should (equal rendered "bd-1"))
          ;; d: bd-1 has dependent bd-2.
          (chaplet-graph--jump-dependents)
          (should (equal chaplet-graph--focus-id "bd-2"))
          (should (equal rendered "bd-2")))))))

(ert-deftest chaplet-test-graph-focus-no-rebind ()
  "n/p/d/f move focus without rebinding node events or re-layouting.
Spies on `chaplet-graph--bind-node-events' and `chaplet-graph--layout':
these run only on a full `chaplet-graph--render' (node set change),
never on focus moves."
  (let ((binds 0) (layouts 0)
        ;; Capture before cl-letf: building the fixture calls the real
        ;; layout, which must not recurse into the spy.
        (orig-layout (symbol-function 'chaplet-graph--layout)))
    (with-temp-buffer
      (let ((f (chaplet-test--graph-fixture)))
        (setq-local chaplet-graph--nodes (car f))
        (setq-local chaplet-graph--edges (cdr f))
        (setq-local chaplet-graph--focus-id "bd-2")
        (setq-local chaplet-graph--text-mode t)
        (cl-letf (((symbol-function 'display-images-p) (lambda () nil))
                  ((symbol-function 'chaplet-graph--bind-node-events)
                   (lambda (_nodes) (cl-incf binds)))
                  ((symbol-function 'chaplet-graph--layout)
                   (lambda (nodes) (cl-incf layouts)
                     (funcall orig-layout nodes))))
          ;; n/p cycle still works and pays no full render.
          (chaplet-graph--focus-next)
          (should (equal chaplet-graph--focus-id "bd-3"))
          (chaplet-graph--focus-prev)
          (should (equal chaplet-graph--focus-id "bd-2"))
          ;; f jumps to a dependency of bd-2.
          (chaplet-graph--jump-deps)
          (should (equal chaplet-graph--focus-id "bd-1"))
          ;; d jumps to a dependent of bd-1.
          (chaplet-graph--jump-dependents)
          (should (equal chaplet-graph--focus-id "bd-2"))
          (should (= binds 0))
          (should (= layouts 0)))))))

(ert-deftest chaplet-test-graph-focus-image-redraw ()
  "Image-mode focus moves regenerate the SVG and replace the image in
place without rebinding node events."
  (let ((binds 0) (imgs 0))
    (cl-letf (((symbol-function 'display-images-p) (lambda () t))
              ((symbol-function 'svg-image)
               (lambda (&rest _) (cl-incf imgs) '(image :type svg :data "")))
              ((symbol-function 'chaplet-graph--bind-node-events)
               (lambda (_nodes) (cl-incf binds))))
      (with-temp-buffer
        (let ((f (chaplet-test--graph-fixture)))
          ;; Full render installs bindings once and inserts one image.
          (chaplet-graph--render (car f) (cdr f) nil)
          (should (= binds 1))
          (should (= imgs 1))
          (should-not chaplet-graph--text-mode)
          (let ((before (buffer-size)))
            ;; n regenerates only the SVG image, no event rebinding.
            (chaplet-graph--focus-next)
            (should (equal chaplet-graph--focus-id "bd-1"))
            (should (= imgs 2))
            (should (= binds 1))
            (should (= (buffer-size) before)))
          (kill-buffer (current-buffer)))))))

(ert-deftest chaplet-test-graph-text-fallback ()
  "Render falls back to a navigable gutter-tree text without images."
  (cl-letf (((symbol-function 'display-images-p) (lambda () nil)))
    (with-temp-buffer
      (let ((f (chaplet-test--graph-fixture)))
        (chaplet-graph--render (car f) (cdr f) "bd-1")
        (should chaplet-graph--text-mode)
        (should (string-match-p "▶\\[bd-1\\]" (buffer-string)))
        (should (string-match-p "missing-dep.*~" (buffer-string)))
        ;; Gutter glyphs (│ └ ┐), not column-per-layer ──→ connectors.
        (should (string-match-p "└┐" (buffer-string)))
        (should (string-match-p "└│" (buffer-string)))
        (should-not (string-match-p "──" (buffer-string)))
        (should-not (string-match-p "→" (buffer-string)))
        ;; Focus keys operate on the text outline (marker moves).
        (chaplet-graph--focus-next)
        (should (string-match-p "▶\\[bd-2\\]" (buffer-string)))))))

;;; chaplet-graph ASCII renderer tests (uvy.9)

(defun chaplet-test-graph-text (focus-id)
  "Render the graph fixture as ASCII text; return the buffer string."
  (cl-letf (((symbol-function 'display-images-p) (lambda () nil)))
    (with-temp-buffer
      (let ((f (chaplet-test--graph-fixture)))
        (chaplet-graph--render (car f) (cdr f) focus-id)
        (buffer-string)))))

(defun chaplet-test--text-canvas (beads &optional focus-id)
  "Render BEADS (bead alists) through the gutter-tree; return the string."
  (let ((layout (chaplet-graph--layout (chaplet-graph--nodes beads))))
    (chaplet-graph--text-canvas (car layout) (cdr layout) focus-id)))

(defun chaplet-test--text-node-ids (beads &optional focus-id)
  "Return node ids in line order from the gutter-tree render of BEADS."
  (let ((ids nil))
    (dolist (line (split-string (chaplet-test--text-canvas beads focus-id) "\n"))
      (when (string-match "\\[\\([^]]+\\)\\]" line)
        (push (match-string 1 line) ids)))
    (nreverse ids)))

(defun chaplet-test--text-box-cols (beads &optional focus-id)
  "Return the `[' column of each node box in the gutter render of BEADS."
  (let ((cols nil))
    (dolist (line (split-string (chaplet-test--text-canvas beads focus-id) "\n"))
      (when (string-match "\\[\\([^]]+\\)\\]" line)
        (push (match-beginning 0) cols)))
    (nreverse cols)))

(ert-deftest chaplet-test-graph-text-columns ()
  "Gutter-tree renderer lays out one node per line in topological order."
  (let ((s (chaplet-test--text-canvas chaplet-test--graph-beads)))
    ;; Deps precede their dependents, one node per line (ghost lane threaded).
    (should (equal (chaplet-test--text-node-ids chaplet-test--graph-beads)
                   '("bd-1" "missing-dep" "bd-2" "bd-3")))
    ;; Gutter indentation grows with the open lanes (└│/└┐), not columns.
    (should (string-match-p "└│" s))
    (should (string-match-p "└┐" s))))

(ert-deftest chaplet-test-graph-text-edges ()
  "Gutter-tree renderer draws `└┐' merge buses and `│' lane continuations."
  (let ((beads '(((id . "a") (title . "one") (status . "open")
                  (dependencies . nil))
                 ((id . "b") (title . "two") (status . "open")
                  (dependencies . nil))
                 ((id . "c") (title . "three") (status . "open")
                  (dependencies . ("a" "b"))))))
    (let ((s (chaplet-test--text-canvas beads)))
      ;; a's lane stays open while b prints → `│' continuation.
      (should (string-match-p "│  \\[b\\]" s))
      ;; c merges both lanes with a `└┐' bus.
      (should (string-match-p "└┐" s))
      ;; No old column-per-layer `──→' connectors.
      (should-not (string-match-p "──" s))
      (should-not (string-match-p "→" s)))))

(ert-deftest chaplet-test-graph-text-chain ()
  "A linear chain renders as right-growing `└' steps; each node once."
  (let ((beads '(((id . "a") (title . "Alpha") (status . "open")
                  (dependencies . nil))
                 ((id . "b") (title . "Beta") (status . "open")
                  (dependencies . ("a")))
                 ((id . "c") (title . "Gamma") (status . "open")
                  (dependencies . ("b"))))))
    (let ((s (chaplet-test--text-canvas beads)))
      (should (equal (chaplet-test--text-node-ids beads) '("a" "b" "c")))
      ;; Each dependent steps onto the `└' glyph of its parent lane.
      (should (string-match-p "└  \\[b\\]" s))
      (should (string-match-p "└  \\[c\\]" s))
      ;; Linear chain: no merges or continuations.
      (should-not (string-match-p "┐" s))
      (should-not (string-match-p "│" s)))))

(ert-deftest chaplet-test-graph-text-fork ()
  "A fan-out opens two lanes; `│'/`└' thread the branch continuations."
  (let ((beads '(((id . "a") (title . "Root") (status . "open")
                  (dependencies . nil))
                 ((id . "b") (title . "B") (status . "open")
                  (dependencies . ("a")))
                 ((id . "c") (title . "C") (status . "open")
                  (dependencies . ("a")))
                 ((id . "d") (title . "D") (status . "open")
                  (dependencies . ("b")))
                 ((id . "e") (title . "E") (status . "open")
                  (dependencies . ("c"))))))
    (let ((s (chaplet-test--text-canvas beads)))
      (should (equal (chaplet-test--text-node-ids beads)
                     '("a" "b" "c" "d" "e")))
      ;; Two lanes open at once: c steps right while b's lane continues.
      (should (string-match-p "└│" s))
      ;; d continues c's lane (│) while stepping onto b's (└).
      (should (string-match-p "│└" s)))))

(ert-deftest chaplet-test-graph-text-diamond ()
  "A diamond node appears once; its lane threads both dependents; D merges."
  (let ((beads '(((id . "A") (title . "Top") (status . "open")
                  (dependencies . nil))
                 ((id . "B") (title . "Bmid") (status . "open")
                  (dependencies . ("A")))
                 ((id . "C") (title . "Cmid") (status . "open")
                  (dependencies . ("A")))
                 ((id . "D") (title . "Bot") (status . "open")
                  (dependencies . ("B" "C"))))))
    (let ((s (chaplet-test--text-canvas beads)))
      ;; A appears once even though it has two dependents.
      (should (equal (chaplet-test--text-node-ids beads)
                     '("A" "B" "C" "D")))
      ;; A's lane threads to both B (└) and C (└│ continuation).
      (should (string-match-p "└  \\[B\\]" s))
      (should (string-match-p "└│" s))
      ;; D merges B and C with a └┐ bus.
      (should (string-match-p "└┐" s)))))

(ert-deftest chaplet-test-graph-text-merge-bus ()
  "A 3-dep node draws a `└─…─┐' merge bus into itself."
  (let ((beads '(((id . "A") (title . "One") (status . "open")
                  (dependencies . nil))
                 ((id . "B") (title . "Two") (status . "open")
                  (dependencies . nil))
                 ((id . "C") (title . "Three") (status . "open")
                  (dependencies . nil))
                 ((id . "D") (title . "Merge") (status . "open")
                  (dependencies . ("A" "B" "C"))))))
    (let ((s (chaplet-test--text-canvas beads)))
      (should (string-match-p "└─┐" s))      ; └ leftmost, ─ span, ┐ rightmost
      (should (string-match-p "│" s))        ; root lanes continue above
      (should (string-match-p "││" s)))))    ; two lanes open for C

(ert-deftest chaplet-test-graph-text-width ()
  "Gutter-tree width is bounded by open lanes + box width, not DAG depth."
  (let* ((beads '(((id . "A") (title . "One") (status . "open")
                   (dependencies . nil))
                  ((id . "B") (title . "Two") (status . "open")
                   (dependencies . nil))
                  ((id . "C") (title . "Three") (status . "open")
                   (dependencies . nil))
                  ((id . "D") (title . "Merge") (status . "open")
                   (dependencies . ("A" "B" "C")))))
         (nodes (chaplet-graph--nodes beads))
         (box-width (apply #'max
                           (mapcar (lambda (n) (string-width
                                                (chaplet-graph--text-node-line n nil)))
                                   nodes)))
         (max-lanes 3)                  ; A, B, C all open before D merges
         (s (chaplet-test--text-canvas beads))
         (widths (mapcar #'string-width (split-string s "\n"))))
    (dolist (w widths)
      (should (<= w (+ max-lanes 1 box-width))))
    ;; Far narrower than the old depth-proportional layout (< 80 cols).
    (should (< (apply #'max widths) 80))))

(ert-deftest chaplet-test-graph-text-truncation-e2e ()
  "Titles over the default 20-col title-max truncate with `…' end-to-end."
  (should (= chaplet-graph--text-title-max 20))
  (let* ((long (make-string 40 ?x))
         (beads (list (list (cons 'id "bd-9") (cons 'title long)
                            (cons 'status "open") (cons 'issue_type "task")
                            (cons 'dependencies nil))))
         (s (chaplet-test--text-canvas beads)))
    (should (string-match-p "…" s))
    ;; Truncated to 19 x's + ellipsis (fits the 20-column budget).
    (should (string-match-p (concat (make-string 19 ?x) "…") s))
    (should-not (string-match-p (make-string 20 ?x) s))))

(ert-deftest chaplet-test-graph-text-align-default ()
  "`chaplet-graph--text-align' defaults to nil; boxes stay ragged."
  (should (null chaplet-graph--text-align))
  ;; bd-1 (no deps) starts at column 2; bd-2 threads a `└│' lane → column 4.
  (should (equal (chaplet-test--text-box-cols chaplet-test--graph-beads)
                 '(2 3 4 4)))
  (let ((cols (chaplet-test--text-box-cols chaplet-test--graph-beads)))
    (should-not (= (car cols) (car (last cols))))))

(ert-deftest chaplet-test-graph-text-align ()
  "`chaplet-graph--text-align' non-nil aligns every node box at one column."
  (let ((chaplet-graph--text-align t))
    (let* ((cols (chaplet-test--text-box-cols chaplet-test--graph-beads))
           (s (chaplet-test--text-canvas chaplet-test--graph-beads)))
      (should (= (length cols) 4))
      (dolist (c (cdr cols))
        (should (= c (car cols))))
      ;; All boxes start after the widest gutter (column 4 here).
      (should (= (car cols) 4))
      ;; Lane-threading glyphs preserved (algorithm untouched).
      (should (string-match-p "└" s))
      (should (string-match-p "│" s))
      (should (string-match-p "┐" s)))))

(defvar chaplet-test--graph-fanout-beads
  '(((id . "r1") (title . "one") (status . "open") (dependencies . nil))
    ((id . "r2") (title . "two") (status . "open") (dependencies . nil))
    ((id . "r3") (title . "three") (status . "open") (dependencies . nil))
    ((id . "r4") (title . "four") (status . "open") (dependencies . nil))
    ((id . "r5") (title . "five") (status . "open") (dependencies . nil))
    ((id . "r6") (title . "six") (status . "open") (dependencies . nil))
    ((id . "m") (title . "merge") (status . "open")
     (dependencies . ("r1" "r2" "r3" "r4" "r5" "r6"))))
  "Six roots merging into one node: 6 concurrent lanes (high fan-out).")

(ert-deftest chaplet-test-graph-text-lane-max-default ()
  "`chaplet-graph--text-lane-max' defaults to nil; output unchanged."
  (should (null chaplet-graph--text-lane-max))
  ;; Existing fixture's boxes stay at their default ragged columns.
  (should (equal (chaplet-test--text-box-cols chaplet-test--graph-beads)
                 '(2 3 4 4))))

(ert-deftest chaplet-test-graph-text-lane-max-unlimited ()
  "nil cap renders every lane; the merge bus spans all 6 lanes."
  (let ((chaplet-graph--text-lane-max nil))
    (let ((s (chaplet-test--text-canvas chaplet-test--graph-fanout-beads)))
      (should (equal (chaplet-test--text-node-ids chaplet-test--graph-fanout-beads)
                     '("r1" "r2" "r3" "r4" "r5" "r6" "m")))
      ;; Merge line's gutter reaches the rightmost (6th) lane.
      (should (string-match-p "└────┐" s))
      (should (>= (apply #'max
                         (mapcar (lambda (c) (- c 2))
                                 (chaplet-test--text-box-cols
                                  chaplet-test--graph-fanout-beads)))
                  6)))))

(ert-deftest chaplet-test-graph-text-lane-max ()
  "`chaplet-graph--text-lane-max' caps rendered gutter width; boxes intact."
  (let ((chaplet-graph--text-lane-max 3))
    (let ((s (chaplet-test--text-canvas chaplet-test--graph-fanout-beads)))
      ;; Every node still appears exactly once.
      (should (equal (chaplet-test--text-node-ids chaplet-test--graph-fanout-beads)
                     '("r1" "r2" "r3" "r4" "r5" "r6" "m")))
      ;; No rendered gutter exceeds the cap (box column = gutter + 2).
      (dolist (w (mapcar (lambda (c) (- c 2))
                         (chaplet-test--text-box-cols
                          chaplet-test--graph-fanout-beads)))
        (should (<= w 3)))
      ;; The merge bus is truncated at the cap: `┐' lane is hidden.
      (should-not (string-match-p "┐" s))
      ;; The node box still follows the capped gutter.
      (should (string-match-p "└──  \\[m\\]" s)))))

(ert-deftest chaplet-test-graph-text-focus ()
  "ASCII renderer marks the focused node with a ▶ prefix."
  (let ((s (chaplet-test-graph-text "bd-2")))
    (should (string-match-p "▶\\[bd-2\\]" s))
    (should-not (string-match-p "▶\\[bd-1\\]" s)))
  (should-not (string-match-p "▶" (chaplet-test-graph-text nil))))

(ert-deftest chaplet-test-graph-text-ghost ()
  "Ghost nodes carry a `~' marker in the ASCII renderer."
  (let ((s (chaplet-test-graph-text nil)))
    (should (string-match-p "missing-dep.*~" s))))

(ert-deftest chaplet-test-graph-text-truncation ()
  "Titles longer than `chaplet-graph--text-title-max' are truncated."
  (let ((long (make-string 60 ?x)))
    (should (equal (chaplet-graph--text-truncate "ok") "ok"))
    (should (string-suffix-p "…" (chaplet-graph--text-truncate long)))
    (should (<= (string-width (chaplet-graph--text-truncate long))
                chaplet-graph--text-title-max))
    ;; Full render shows the ellipsis.
    (cl-letf (((symbol-function 'display-images-p) (lambda () nil)))
      (with-temp-buffer
        (let* ((beads (list (list (cons 'id "bd-9")
                                  (cons 'title long)
                                  (cons 'status "open")
                                  (cons 'issue_type "task")
                                  (cons 'dependencies nil))))
               (layout (chaplet-graph--layout (chaplet-graph--nodes beads))))
          (chaplet-graph--render (car layout) (cdr layout) nil)
          (should (string-match-p "…" (buffer-string))))))))

(ert-deftest chaplet-test-graph-text-faces ()
  "ASCII renderer applies chaplet-face faces to id and state."
  (with-temp-buffer
    (insert (chaplet-test-graph-text nil))
    (goto-char (point-min))
    (let ((p (search-forward "bd-1" nil t)))
      (should (eq (get-text-property (1- p) 'face) 'chaplet-id)))
    (goto-char (point-min))
    (let ((p (search-forward "deferred" nil t)))
      (should (eq (get-text-property (1- p) 'face) 'chaplet-staged)))))

(ert-deftest chaplet-test-graph-refresh-preserves-focus ()
  "`chaplet-graph--refresh' re-fetches and keeps focus when still present."
  (let ((fetched :unset))
    (cl-letf (((symbol-function 'chaplet-bd-graph-data)
               (lambda (filters)
                 (setq fetched filters)
                 chaplet-test--graph-beads)))
      (with-temp-buffer
        (setq-local chaplet-graph--view 'open)
        (setq-local chaplet-graph--focus-id "bd-2")
        (chaplet-graph--refresh)
        (should (equal fetched '((:status . "open"))))
        (should (equal chaplet-graph--focus-id "bd-2"))
        (should (= (length chaplet-graph--nodes) 4))
        ;; Focus is dropped when the node no longer exists.
        (setq-local chaplet-graph--focus-id "bd-99")
        (chaplet-graph--refresh)
        (should-not chaplet-graph--focus-id)))))

(ert-deftest chaplet-test-graph-mouse-bindings ()
  "Render installs `[ID mouse-1]'/'[ID mouse-2]' bindings for every node."
  (with-temp-buffer
    (let ((f (chaplet-test--graph-fixture)))
      (chaplet-graph--render (car f) (cdr f) nil)
      (should (eq (lookup-key chaplet-graph-mode-map [bd-1 mouse-1])
                  'chaplet-graph--open-node))
      (should (eq (lookup-key chaplet-graph-mode-map [bd-1 mouse-2])
                  'chaplet-graph--node-dependents))
      (should (eq (lookup-key chaplet-graph-mode-map [missing-dep mouse-1])
                  'chaplet-graph--open-node)))))

(ert-deftest chaplet-test-graph-clicked-id ()
  "`chaplet-graph--clicked-id' recovers the id from an image-map click key."
  (cl-letf (((symbol-function 'this-command-keys-vector)
             (lambda () [bd-3 mouse-1])))
    (should (eq (chaplet-graph--clicked-id) 'bd-3)))
  (cl-letf (((symbol-function 'this-command-keys-vector)
             (lambda () [mouse-1])))
    (should-not (chaplet-graph--clicked-id))))

;;; chaplet-bar tests (uvy.8)

(defun chaplet-test-bar--keys (s)
  "Return the key strings inside \"[KEY]\" segments of rendered bar S."
  (let ((pos 0) keys)
    (while (string-match "\\[[^]]+\\]" s pos)
      (push (substring s (1+ (match-beginning 0)) (1- (match-end 0))) keys)
      (setq pos (match-end 0)))
    (nreverse keys)))

(ert-deftest chaplet-test-bar-list-installed ()
  "The main list buffer's mode line carries the keybinding bar."
  (cl-letf (((symbol-function 'chaplet-list--fetch) (lambda (_view) nil)))
    (with-temp-buffer
      (chaplet-list-mode)
      (should (member '(:eval chaplet-bar--rendered) mode-line-format))
      (should chaplet-bar--installed)
      (should (string-match-p "\\[v\\]" chaplet-bar--rendered))
      (should (string-match-p "\\[s\\]" chaplet-bar--rendered))
      (should (string-match-p "\\[q\\]" chaplet-bar--rendered))
      (should (string-match-p "\\[mouse-1\\]" chaplet-bar--rendered))
      (should (equal chaplet-bar--rendered (chaplet-bar--render))))))

(ert-deftest chaplet-test-bar-graph-installed ()
  "The graph buffer's mode line carries the keybinding bar."
  (with-temp-buffer
    (let ((f (chaplet-test--graph-fixture)))
      (chaplet-graph--render (car f) (cdr f) nil))
    (should (member '(:eval chaplet-bar--rendered) mode-line-format))
    (should (string-match-p "\\[n\\]" chaplet-bar--rendered))
    (should (string-match-p "\\[p\\]" chaplet-bar--rendered))
    (should (string-match-p "\\[RET\\]" chaplet-bar--rendered))
    (should (string-match-p "\\[mouse-1\\]" chaplet-bar--rendered))
    (should (string-match-p "\\[mouse-2\\]" chaplet-bar--rendered))
    (should (equal chaplet-bar--rendered (chaplet-bar--render)))))

(ert-deftest chaplet-test-bar-list-keys-match-keymap ()
  "Every key listed in the main bar is bound in `chaplet-list-mode-map'.
`c' (closed toggle) is deliberately absent — the list keymap does not
bind it; `s' reflects the real binding (graph)."
  (cl-letf (((symbol-function 'chaplet-list--fetch) (lambda (_view) nil)))
    (with-temp-buffer
      (chaplet-list-mode)
      (let ((keys (chaplet-test-bar--keys chaplet-bar--rendered)))
        (dolist (k keys)
          (should (lookup-key chaplet-list-mode-map (kbd k))))
        (should-not (member "c" keys))
        (should (member "s" keys))))))

(ert-deftest chaplet-test-bar-graph-keys-match-keymap ()
  "Keyboard keys listed in the graph bar are bound in the graph keymap.
Mouse entries reflect the per-node hot-spot bindings installed on render."
  (with-temp-buffer
    (let ((f (chaplet-test--graph-fixture)))
      (chaplet-graph--render (car f) (cdr f) nil))
    (let ((keys (chaplet-test-bar--keys chaplet-bar--rendered)))
      (dolist (k (cl-remove-if (lambda (k) (member k '("mouse-1" "mouse-2")))
                               keys))
        (should (lookup-key chaplet-graph-mode-map (kbd k))))
      (should (member "mouse-1" keys))
      (should (member "mouse-2" keys))
      (should (eq (lookup-key chaplet-graph-mode-map [bd-1 mouse-1])
                  'chaplet-graph--open-node)))))

(ert-deftest chaplet-test-bar-unrelated-buffer ()
  "Buffers that never install the bar have no bar mode-line element."
  (with-temp-buffer
    (should-not (member '(:eval chaplet-bar--rendered) mode-line-format))
    (should-not (bound-and-true-p chaplet-bar--installed))
    (should (string= (chaplet-bar--render) ""))))

(ert-deftest chaplet-test-bar-idempotent ()
  "Installing the bar twice appends a single mode-line element."
  (with-temp-buffer
    (chaplet-bar--install)
    (chaplet-bar--install)
    (should (= 1 (cl-count '(:eval chaplet-bar--rendered) mode-line-format
                           :test #'equal)))))

(ert-deftest chaplet-test-bar-render-cached ()
  "`chaplet-bar--install' renders once; the mode-line element only reads
the cached string, so `chaplet-bar--render' is not called on redisplay."
  (with-temp-buffer
    (let ((calls 0)
          (orig (symbol-function 'chaplet-bar--render)))
      (cl-letf (((symbol-function 'chaplet-bar--render)
                 (lambda ()
                   (cl-incf calls)
                   (funcall orig))))
        (chaplet-bar--install)
        (should (= 1 calls)))
      (should (member '(:eval chaplet-bar--rendered) mode-line-format))
      (should-not (member '(:eval (chaplet-bar--render)) mode-line-format))
      (should (equal chaplet-bar--rendered (chaplet-bar--render))))))

(ert-deftest chaplet-test-bar-reinstall-renders ()
  "Re-invoking `chaplet-bar--install' re-renders the cached string
without duplicating the mode-line element."
  (with-temp-buffer
    (setq-local chaplet-bar--map (make-sparse-keymap))
    (define-key chaplet-bar--map (kbd "x") #'ignore)
    (define-key chaplet-bar--map (kbd "y") #'ignore)
    (setq-local chaplet-bar--specs '(("x" . "ex")))
    (chaplet-bar--install)
    (should (string-match-p "\\[x\\]" chaplet-bar--rendered))
    (setq-local chaplet-bar--specs '(("y" . "why")))
    (chaplet-bar--install)
    (should (string-match-p "\\[y\\]" chaplet-bar--rendered))
    (should-not (string-match-p "\\[x\\]" chaplet-bar--rendered))
    (should (equal chaplet-bar--rendered (chaplet-bar--render)))
    (should (= 1 (cl-count '(:eval chaplet-bar--rendered) mode-line-format
                           :test #'equal)))))

(ert-deftest chaplet-test-bar-leading ()
  "The bar is prepended, so it stays visible even when the mode line
ends in a space-filler (regression: appending after the filler clipped it)."
  (with-temp-buffer
    (chaplet-bar--install)
    (let ((mlf (if (equal (car mode-line-format) "%e")
                   (cdr mode-line-format)
                 mode-line-format)))
      (should (equal (car mlf) '(:eval chaplet-bar--rendered))))))

(ert-deftest chaplet-test-bar-not-after-filler ()
  "The bar is inserted before `mode-line-end-spaces', not clipped after it."
  (with-temp-buffer
    (chaplet-bar--install)
    (let ((bar-pos (cl-position '(:eval chaplet-bar--rendered) mode-line-format
                                :test #'equal))
          (filler-pos (cl-position 'mode-line-end-spaces mode-line-format)))
      (should bar-pos)
      (should (or (null filler-pos) (< bar-pos filler-pos))))))

(ert-deftest chaplet-test-bd-invoke-rejects-nil-argument ()
  "A missing bead id must not reach `call-process'.
`(apply #'call-process ... (list ... nil))' raises the opaque
\"apply: Wrong type argument: stringp, nil\" in the echo area; the bridge
reports the incomplete command instead."
  (should-error (chaplet-bd--invoke (list "show" "--json" "--long" nil))
                :type 'user-error)
  (should-error (chaplet-bd-show nil) :type 'user-error))

(ert-deftest chaplet-test-list-open-without-bead-at-point ()
  "RET on a non-row line (e.g. an empty view) reports no bead at point."
  (should-error (chaplet-list-open nil) :type 'user-error)
  (should-error (chaplet-list--show-raw nil) :type 'user-error))

(ert-deftest chaplet-test-detail-rejects-empty-id ()
  "The detail buffer refuses a nil or empty bead id."
  (should-error (chaplet-detail nil) :type 'user-error)
  (should-error (chaplet-detail "") :type 'user-error))

(provide 'chaplet-test)
;;; chaplet-test.el ends here
