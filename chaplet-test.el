;;; chaplet-test.el --- ERT tests for chaplet -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'chaplet-bd)
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

(ert-deftest chaplet-test-bd-create ()
  "`chaplet-bd-create' returns the new id."
  (let ((chaplet-bd-program chaplet-test--fake-bd))
    (should (equal (chaplet-bd-create "my title" "task" "desc") "bd-99"))))

(ert-deftest chaplet-test-bd-write-failure ()
  "Writes return nil when bd exits non-zero."
  (cl-letf (((symbol-function 'chaplet-bd--invoke)
             (lambda (_args) (cons 1 ""))))
    (should (eq (chaplet-bd-defer "bd-1") nil))
    (should (eq (chaplet-bd-undefer "bd-1") nil))))

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
        (should (equal (aref row 0) "bd-1"))
        (should (equal (aref row 1) "task"))
        (should (equal (substring-no-properties (aref row 2)) "deferred"))
        (should (equal (aref row 3) "2"))
        (should (equal (aref row 4) "✔"))
        (should (equal (aref row 5) "Do thing"))))))

(ert-deftest chaplet-test-list-entry-not-staged ()
  "Staged? column is empty for non-staged beads; P0 renders as \"0\"."
  (let ((bead '((id . "bd-3") (title . "x") (status . "open")
                (priority . 0) (issue_type . "bug") (labels . nil))))
    (let ((entry (chaplet-list--entry bead)))
      (should (equal (aref (cadr entry) 3) "0"))
      (should (equal (aref (cadr entry) 4) "")))))

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
    (should (equal (buffer-name) "*chaplet:detail:bd-1*"))
    (should buffer-read-only)
    (should (string-match-p "# one" (buffer-string)))
    (should (string-match-p "## Description" (buffer-string)))
    (should (string-match-p "## Design" (buffer-string)))
    (should (string-match-p "## Acceptance" (buffer-string)))
    (should (string-match-p "## Comments" (buffer-string)))
    (should (string-match-p "- \\*\\*alice\\*\\* — nice bead" (buffer-string)))
    (kill-buffer)))

(ert-deftest chaplet-test-detail-mode-no-markdown ()
  "Mode falls back to fundamental + font-lock without markdown-mode."
  (cl-letf (((symbol-function 'require)
             (lambda (_feature &rest _) nil)))
    (with-temp-buffer
      (should (eq (chaplet-detail--activate-major-mode) 'fundamental-mode))
      (should (eq major-mode 'fundamental-mode)))))

(ert-deftest chaplet-test-graph-dot-available-p ()
  "`chaplet-graph--dot-available-p' detects the dot program."
  (let ((chaplet-graph-dot-program "chaplet-no-such-dot-program-xyz"))
    (should-not (chaplet-graph--dot-available-p)))
  (let ((chaplet-graph-dot-program
         (expand-file-name "test/fake-dot" chaplet-test--root)))
    (should (chaplet-graph--dot-available-p))))

(ert-deftest chaplet-test-graph-dot->svg ()
  "`chaplet-graph--dot->svg' pipes DOT through dot and returns SVG."
  (let ((chaplet-graph-dot-program
         (expand-file-name "test/fake-dot" chaplet-test--root)))
    (let ((svg (chaplet-graph--dot->svg "digraph {}")))
      (should (stringp svg))
      (should (string-match-p "<svg" svg)))))

(ert-deftest chaplet-test-graph-render ()
  "`chaplet-graph--render' builds the `*chaplet:graph*' buffer."
  (chaplet-graph--render "<svg/>")
  (should (get-buffer "*chaplet:graph*"))
  (should (with-current-buffer "*chaplet:graph*"
            (string-match-p "<svg/>" (buffer-string))))
  (kill-buffer "*chaplet:graph*"))

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
  "`chaplet-approve' undefer's the bead at point and refreshes."
  (let (undefer-id refreshed)
    (cl-letf (((symbol-function 'chaplet-bd-undefer)
               (lambda (id) (setq undefer-id id) t))
              ((symbol-function 'chaplet-list-refresh)
               (lambda () (setq refreshed t)))
              ((symbol-function 'chaplet-transient--id-at-point)
               (lambda () "bd-1")))
      (chaplet-approve)
      (should (equal undefer-id "bd-1"))
      (should refreshed))))

(ert-deftest chaplet-test-transient-reject ()
  "`chaplet-reject' prompts feedback and comments \"rejected: <fb>\"."
  (let (commented-id commented-text)
    (cl-letf (((symbol-function 'read-string)
               (lambda (&rest _) "needs work"))
              ((symbol-function 'chaplet-bd-comment)
               (lambda (id text) (setq commented-id id commented-text text) t))
              ((symbol-function 'chaplet-list-refresh)
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
              ((symbol-function 'chaplet-list-refresh)
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
              ((symbol-function 'chaplet-list-refresh)
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
              ((symbol-function 'chaplet-list-refresh)
               (lambda () nil)))
      (chaplet-new)
      (should (equal created '("my bead" "task" "the desc"))))))

(ert-deftest chaplet-test-transient-refresh ()
  "`chaplet-refresh' refreshes the list."
  (let ((refreshed nil))
    (cl-letf (((symbol-function 'chaplet-list-refresh)
               (lambda () (setq refreshed t))))
      (chaplet-refresh)
      (should refreshed))))

(ert-deftest chaplet-test-transient-graph-delegates ()
  "`chaplet-graph' is fboundp (graph module); the menu delegates to it."
  (should (fboundp 'chaplet-graph)))

(ert-deftest chaplet-test-transient-detail-approve ()
  "`chaplet-transient-approve' undefer's an explicit id without refresh."
  (let (undefer-id)
    (cl-letf (((symbol-function 'chaplet-bd-undefer)
               (lambda (id) (setq undefer-id id) t)))
      (chaplet-transient-approve "bd-7")
      (should (equal undefer-id "bd-7")))))

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
          (should (equal (buffer-name) "*chaplet:inbox*"))
          (should (fboundp 'chaplet-transient))
          (should (eq (lookup-key chaplet-list-mode-map (kbd "?"))
                      'chaplet-transient)))
      (kill-buffer "*chaplet:inbox*"))))

(ert-deftest chaplet-test-graph-headless-render ()
  "`chaplet-graph--render' skips image-mode when display-images-p is nil."
  :tags '(:chaplet)
  (cl-letf (((symbol-function 'display-images-p) (lambda () nil))
            ((symbol-function 'image-mode)
             (lambda () (error "image-mode should not be called"))))
    (let ((buf (chaplet-graph--render "<svg/>")))
      (should buf)
      (should (with-current-buffer buf
                (string-match-p "<svg/>" (buffer-string))))))
  (kill-buffer "*chaplet:graph*"))

(ert-deftest chaplet-test-graph-headless-fallback ()
  "`chaplet-graph' falls back to raw DOT when dot is absent (headless)."
  :tags '(:chaplet)
  (let ((chaplet-bd-program chaplet-test--fake-bd)
        (chaplet-graph-dot-program "chaplet-no-such-dot-program-xyz"))
    (should-not (chaplet-graph--dot-available-p))
    (chaplet-graph)
    (should (get-buffer "*chaplet:graph*"))
    (should (with-current-buffer "*chaplet:graph*"
              (string-match-p "digraph" (buffer-string))))
    (kill-buffer "*chaplet:graph*")))

(ert-deftest chaplet-test-list-v-key ()
  "`v' in `chaplet-list-mode-map' switches views."
  :tags '(:chaplet)
  (should (eq (lookup-key chaplet-list-mode-map (kbd "v"))
              'chaplet-list-set-view)))

(ert-deftest chaplet-test-list-set-view-closed ()
  "`chaplet-list-set-view' to `closed` renders closed beads."
  :tags '(:chaplet)
  (cl-letf (((symbol-function 'chaplet-bd-query)
             (lambda (_q) '(((id . "bd-9") (status . "closed")
                             (issue_type . "task") (title . "done"))))))
    (unwind-protect
        (progn
          (chaplet-list-set-view 'closed)
          (should (get-buffer "*chaplet:closed*"))
          (should (with-current-buffer "*chaplet:closed*"
                    (string-match-p "bd-9" (buffer-string)))))
      (kill-buffer "*chaplet:closed*"))))

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

(ert-deftest chaplet-test-graph-include-closed ()
  "`chaplet-graph' with a prefix arg requests closed beads."
  :tags '(:chaplet)
  (let ((captured nil))
    (cl-letf (((symbol-function 'chaplet-bd-graph-dot)
               (lambda (filters) (setq captured filters) nil)))
      (chaplet-graph '(4))                 ; C-u prefix arg
      (should (equal captured '((:closed . t)))))))

(ert-deftest chaplet-test-list-s-key ()
  "`s' in `chaplet-list-mode-map' opens the graph view."
  :tags '(:chaplet)
  (should (eq (lookup-key chaplet-list-mode-map (kbd "s"))
              'chaplet-graph)))

(provide 'chaplet-test)
;;; chaplet-test.el ends here
