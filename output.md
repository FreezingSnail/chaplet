# chaplet-list — interface

tabulated-list bead browser (built on chaplet-bd). Views + filters.

## Commands

```elisp
(chaplet-list)                 ;; entry: open inbox (staged) view
(chaplet-list-mode)            ;; derived from tabulated-list-mode
(chaplet-list-refresh)         ;; re-run current view query, re-render
(chaplet-list-set-view name)   ;; switch view (interactive)
(chaplet-list-open id)         ;; RET → chaplet-detail, else raw bd show buffer
(chaplet-list-filter type label) ;; filter by type/label (server-side)
```

## Helpers (internal)

```elisp
(chaplet-list--staged-p bead)     ;; status=deferred AND (labels nil | "staged" member)
(chaplet-list--view-query view)   ;; view symbol → bd query expr (nil = all)
(chaplet-list--entry bead)        ;; bead alist → (id . [id type state p staged title])
(chaplet-list--fetch view)        ;; bead alists for view (+ active filters)
(chaplet-list--filters->query base filters) ;; compose `field=value' clauses
(chaplet-list--state-face status) ;; status → face symbol
```

## Views registry

`chaplet-list--views` alist: `inbox→"status=deferred AND label=staged"`,
`open→"status=open"`, `in-progress→"status=in_progress"`,
`blocked→"status=blocked"`, `closed→"status=closed"`, `all→nil`
(`all` → `(chaplet-bd-list '((:all . t)))`).

## Staged? approach

`bd list --json` lacks labels. inbox = server-side query
`status=deferred AND label=staged`. Other views: `chaplet-list--staged-p`
falls back to `status=deferred` when labels absent (documented approximation).

## Column format

`[("ID" 12) ("Type" 10) ("State" 12) ("P" 3) ("Staged" 7) ("Title" 60)]`.
State column faces: `chaplet-state-deferred/-in-progress/-blocked/-closed`.
Staged? = "✔" when staged. Buffer `*chaplet:<view>*`.

---

# chaplet-bd — interface

bd CLI bridge. ONLY module touching bd. Reads return elisp (JSON→alists);
writes return t/nil (create returns id string).

## Seam

- `chaplet-bd-program` — defvar, default `"bd"`. Override for tests.

## Reads

```elisp
(chaplet-bd-list &optional filters)     ;; → list of bead alists
(chaplet-bd-query expr)                 ;; → list of bead alists
(chaplet-bd-show id)                    ;; → bead alist | nil
(chaplet-bd-graph-dot &optional filters);; → DOT string | nil
```

## Writes

```elisp
(chaplet-bd-create title type description) ;; → id-string | nil
(chaplet-bd-comment id text)               ;; → boolean
(chaplet-bd-undefer id)                    ;; → boolean (approve)
(chaplet-bd-defer id)                      ;; → boolean
(chaplet-bd-update-design id design)       ;; → boolean
(chaplet-bd-update-acceptance id acc)      ;; → boolean
(chaplet-bd-label id label)                ;; → boolean
```

## Helpers (internal)

```elisp
(chaplet-bd--root)              ;; → project root string (fallback default-directory)
(chaplet-bd--invoke args)       ;; → (exit-code . stdout); runs `bd -C root ARGS`
(chaplet-bd--filters->args filters) ;; → CLI arg list
```

## Bead alist shape (symbol keys, normalized)

`id title description status priority issue_type owner labels defer_until
 design acceptance created_at updated_at`

## Filters alist (keyword → value)

`:status :type :priority :label :limit` → `--flag=value`
`:all :ready :deferred` → bare flag when non-nil
`:id` (graph-dot only) → positional issue id, else `--all`

## bd JSON facts (v1.1.2, verified)

`bd list --json` / `bd show --json --long` fields: `id title description
status priority issue_type owner created_at created_by updated_at
dependencies dependency_count dependent_count comment_count parent`.

**NOT in JSON**: `labels`, `defer_until`, `design`, `acceptance` — these
normalize to nil. Labels live behind `bd label list <id> --json` (separate
command), not hydrated in list/show JSON.

- `bd create <title> -t <type> -d <desc> --silent` → stdout is bare id.
- `bd graph --dot [--all | <id>]` → DOT string.
- `bd label add <id> <label>`, `bd update <id> --design/--acceptance <text>`,
  `bd comment <id> <text>`, `bd undefer <id>`, `bd defer <id>`.

## Tests

`chaplet-test.el` (ERT, tag `chaplet`), `test/fake-bd` (committed fake CLI).

```
emacs -Q --batch -L . -l chaplet-test \
  --eval '(ert-run-tests-batch-and-exit "chaplet-test-")'
```

---

# chaplet-detail — interface

Read-only markdown detail buffer for a single bead.

## Entry

```elisp
(chaplet-detail id)        ;; → read-only buffer *chaplet:detail:<id>* (pop-to-buffer)
(chaplet-detail-mode)      ;; minor keymap: q quit, g refresh, c comment,
                           ;;                a approve, r reject
(chaplet-detail--render bead) ;; bead alist → markdown string (pure)
```

## Rendering

Header line: `# <title>` + `*id:* / *status:* / *priority:* / *type:*
/ *owner:* / *created:*` + optional `*labels:*`.

Sections `## Description` / `## Design` / `## Acceptance` / `## Comments`
(omitted when blank). Each comment renders `- **author** — text`.

## markdown-mode policy

`(require 'markdown-mode nil t)` → markdown-mode if present; else
fundamental-mode + `font-lock-mode` (no hard dep).

## Actions (delegate to chaplet-transient when fboundp)

`chaplet-detail-comment/approve/reject` — call `chaplet-transient-comment/
approve/reject` (with bead id) if fboundp, else `message` fallback.

## bd field discovery (v1.1.2, re-verified for detail)

`bd show <id> --json --long` DOES include `design`, `labels`, and
**`acceptance_criteria`** (not `acceptance`) when set. `chaplet-bd--normalize`
maps `acceptance_criteria` → `acceptance`.

Comments: `bd show <id> --json --long --include-comments` embeds a `comments`
array; equivalently `bd comments <id> --json` → `[{id issue_id author text
created_at}]`. `chaplet-bd-comments` uses the latter.

Corrects earlier note: `design`/`labels`/`acceptance` ARE in show JSON (long)
when present — only `defer_until` is absent.

---

# chaplet-graph — interface

Dependency DAG → inline SVG (Graphviz). No hard Graphviz dep — raw-DOT fallback.

## Entry

```elisp
(chaplet-graph)                 ;; render current scope DAG → *chaplet:graph*
```

## Functions

```elisp
(chaplet-graph--dot-available-p)  ;; → boolean (executable-find of dot program)
(chaplet-graph--dot->svg dot)     ;; DOT string → SVG string | nil (pipe `dot -Tsvg`)
(chaplet-graph--render svg)       ;; SVG string → *chaplet:graph* buffer (image-mode when possible)
(chaplet-graph--show-dot dot)     ;; raw DOT → *chaplet:graph* (fundamental-mode, q quits)
```

## dot invocation

`chaplet-graph-dot-program` — defvar, default `"dot"`. Override for tests.
`chaplet-graph--dot->svg` runs `call-process-region` → `dot -Tsvg`, reads stdin,
writes stdout, returns buffer-string when exit 0, else nil.

## Fallback

dot absent (`chaplet-graph--dot-available-p` nil) → `chaplet-graph--show-dot`
raw DOT + message "dot not found". Render failure (nil SVG) → same fallback +
"graph render failed". Source: `(chaplet-bd-graph-dot nil)` (`bd graph --dot`).

## Tests

`chaplet-test.el` (ERT, tag `chaplet`), `test/fake-dot` (committed fake dot:
emits fixed `<svg ...></svg>`, exit 0). 3 tests: dot-available-p, dot->svg, render.

---

# chaplet-transient — interface

Magit-style `transient` action menu, tailored per bead state. `?` opens it
in `chaplet-list-mode`.

## Entry / Commands

```elisp
(chaplet-transient)              ;; ? → dispatch popup for bead at point
(chaplet-approve)                ;; a — (chaplet-bd-undefer id) + refresh
(chaplet-reject)                 ;; r — read-string fb → (chaplet-bd-comment id "rejected: fb") + refresh
(chaplet-comment)                ;; c — read-string → chaplet-bd-comment + refresh
(chaplet-edit-design)            ;; e — read-string → chaplet-bd-update-design + refresh
(chaplet-new)                    ;; n — title/type/desc prompts → chaplet-bd-create + refresh
(chaplet-refresh)                ;; g — chaplet-list-refresh
(chaplet-graph)                  ;; s — (existing) graph module entry; :if fboundp
```

All write actions (`approve`/`reject`/`comment`/`edit-design`/`new`) accept an
optional ID arg and call `chaplet-transient--refresh` afterwards, which
refreshes the originating list buffer (not the transient buffer).

## State → actions (pure)

```elisp
(chaplet-transient--actions-for-state state)  ;; → list of action symbols
(chaplet-transient--action-visible-p action)  ;; memq against captured state
```

- `deferred` (staged) → `(approve reject comment edit-design)`
- `open` → `(comment edit-design new)`
- everything else (`in_progress`/`blocked`/`closed`/nil) → `(comment)`

Menu suffixes gated by `:if` lambdas on the captured
`chaplet-transient--state`.

## Bead at point

```elisp
(chaplet-transient--id-at-point)    ;; (derived-mode-p 'chaplet-list-mode) → tabulated-list-get-id
(chaplet-transient--state-at-point) ;; id → (chaplet-bd-show id) → status
```

Context captured in prefix BODY before `transient-setup`:
`chaplet-transient--id` / `--state` / `--list-buffer`.

## Detail-buffer delegation (id-taking, no refresh)

```elisp
(chaplet-transient-approve id)  ;; chaplet-bd-undefer
(chaplet-transient-reject  id)  ;; read-string → chaplet-bd-comment "rejected: fb"
(chaplet-transient-comment id)  ;; read-string → chaplet-bd-comment
```

Consumed by `chaplet-detail-approve/reject/comment` (fboundp guard).

## Key binding

`(define-key chaplet-list-mode-map (kbd "?") #'chaplet-transient)` — no
duplicate (chaplet-list-mode-map only bound RET before).

## Dependency

`(require 'transient)` — built-in since Emacs 29 (verified present, Emacs 30.2).

## Tests

Appended to `chaplet-test.el` (tag `chaplet`), 10 new tests:
`actions-for-state`, `action-visible-p`, `approve`, `reject`, `comment`,
`edit-design`, `new`, `refresh`, `graph-delegates`, `detail-approve`.
Mocks via cl-letf on `chaplet-transient--id-at-point` + write/refresh fns.

---

# chaplet — interface

Entry point + global minor mode + keymap. Requires all modules.

## Entry / Commands

```elisp
(chaplet)              ;; M-x chaplet → (chaplet-list-set-view 'inbox)
(chaplet-mode &optional arg) ;; global minor mode (define-minor-mode, :global t)
(chaplet-mode-map)     ;; keymap var: C-c b b → chaplet, C-c b s → chaplet-graph
```

## Requires

`chaplet-bd`, `chaplet-list`, `chaplet-transient`, `chaplet-detail`,
`chaplet-graph` (all direct, all built).

## Keymap

```elisp
(defvar chaplet-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c b b") #'chaplet)
    (define-key map (kbd "C-c b s") #'chaplet-graph)
    map))
```

`?` → `chaplet-transient` already bound in `chaplet-list-mode-map` by
`chaplet-transient.el` (no duplicate).

## install.sh

Doom-aware, idempotent, marker-based. `SNIPPET_MARKER` =
`";; === chaplet (managed by install.sh) ==="`, end marker
`";; === end chaplet ==="`. Detect Doom 3 `~/.config/doom/config.el`
(XDG-aware), fallback `~/.emacs.d/init.el` (mkdir -p parent).
`--install` (default) appends snippet when marker absent; `--uninstall`
awk-strips marker→end inclusive. Plugin dir computed via
`$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)` — not hardcoded.
`set -euo pipefail`.

Snippet:
```elisp
;; === chaplet (managed by install.sh) ===
(add-to-list 'load-path "<plugin-dir>")
(require 'chaplet)
(chaplet-mode 1)
;; === end chaplet ===
```

## Tests

3 new tests (total 40): `chaplet-test-entry-opens-inbox`,
`chaplet-test-mode-map`, `chaplet-test-mode-enable` (tag `:chaplet`).
`chaplet-test-mode-enable` wraps toggle in `unwind-protect` →
`(chaplet-mode -1)` to restore global state.

---

# chaplet-00r.7 — integration (final)

## Load order

`chaplet.el` requires `chaplet-bd` → `chaplet-list` → `chaplet-transient` →
`chaplet-detail` → `chaplet-graph`. Verified: `emacs -Q --batch -L . --eval
'(require (quote chaplet))'` loads clean (no void-function / void-variable).

## Byte-compile

`emacs -Q --batch -L . -f batch-byte-compile chaplet.el chaplet-bd.el
chaplet-list.el chaplet-detail.el chaplet-graph.el chaplet-transient.el`
→ 0 errors. 2 pre-existing warnings (not new):

- `chaplet.el:27:20: Warning: in defcustom for 'chaplet-mode': fails to
  specify containing group`
- `chaplet-detail.el:64:15: Warning: the function 'markdown-mode' is not
  known to be defined.`

## New integration tests (tag `:chaplet`, +5 → total 45)

- `chaplet-test-full-loop-approve` — staged inbox → approve (undefer) →
  bead gone from inbox. Real fake-bd, stateful.
- `chaplet-test-full-loop-reject` — reject → fake-bd records
  `COMMENT <id> rejected: <fb>`; bead stays staged.
- `chaplet-test-smoke-entry` — `chaplet` → `chaplet-list-mode` +
  `*chaplet:inbox*`; `?` bound to `chaplet-transient`.
- `chaplet-test-graph-headless-render` — `display-images-p` nil →
  `image-mode` not called (guard).
- `chaplet-test-graph-headless-fallback` — dot absent → raw-DOT fallback,
  no error in headless batch.

## test/fake-bd (stateful mode)

When `CHAPLET_FAKE_BD_STATE` set: `undefer` records `APPROVED <id>`,
`comment` records `COMMENT <id> <text>`; `query` filters approved ids
(inbox removal observable). Stateless otherwise (existing tests unchanged).
State file: `test/.fake-bd-state` (gitignored, cleaned per-test via
`chaplet-test--with-state` unwind-protect).

## Verify

```
emacs -Q --batch -L . -l chaplet-test \
  --eval '(ert-run-tests-batch-and-exit "chaplet-test-")'
```
→ 45 tests, 45 results as expected, 0 unexpected.

## View switching (chaplet-9q2)

Keybindings:

```elisp
;; chaplet-list-mode-map
(define-key chaplet-list-mode-map (kbd "v") #'chaplet-list-set-view)
;; chaplet-transient.el: "General" group gains
("v" "switch view" chaplet-list-set-view)
```

- `v` in `chaplet-list-mode` → `chaplet-list-set-view` (completing-read
  over inbox/open/in-progress/blocked/closed/all).
- `? v` in transient → same view switch.
- `closed` view renders finished beads (`status=closed`); `all` uses
  `bd list --all`.

## New tests (tag `:chaplet`, +2 → total 47)

- `chaplet-test-list-v-key` — `lookup-key chaplet-list-mode-map (kbd "v")`
  → `chaplet-list-set-view`.
- `chaplet-test-list-set-view-closed` — cl-letf `chaplet-bd-query` →
  one closed bead; `chaplet-list-set-view 'closed` builds `*chaplet:closed*`
  buffer containing "bd-9".

Verify: 47 tests, 47 results as expected, 0 unexpected.

---

# chaplet-7g5 — graph: include closed (prefix arg toggle)

## chaplet-bd

`chaplet-bd-graph-dot (&optional filters)` now honors `(:closed . t)`:

- `(:id . "...")` → `("graph" "--dot" ID)`
- `(:closed . t)` → `("list" "--format" "dot" "--all")` (includes closed)
- else → `("graph" "--dot" "--all")` (open only)

`bd graph` has no closed-inclusive flag; `bd list --format dot --all` returns
all beads (closed marked `(closed)`).

## chaplet-graph

`(chaplet-graph &optional include-closed)` with `(interactive "P")`.
Prefix arg (`C-u s`) → `(chaplet-bd-graph-dot '((:closed . t)))`.

## chaplet-list

`s` bound in `chaplet-list-mode-map` → `chaplet-graph` (guarded:
`(unless (lookup-key ... (kbd "s"))`). `s` free (tabulated-list binds `S`
for sort, not `s`). `(require 'chaplet-graph)` added.

## Tests

+3 (total 50):

- `chaplet-test-bd-graph-dot-args` — nil→graph --dot --all;
  `(:closed . t)`→list --format dot --all; `(:id . "bd-9")`→graph --dot bd-9.
- `chaplet-test-graph-include-closed` — `(chaplet-graph '(4))` forwards
  `((:closed . t))`.
- `chaplet-test-list-s-key` — `s` → `chaplet-graph`.

Verify: 50 tests, 50 results as expected, 0 unexpected.
