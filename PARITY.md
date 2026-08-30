# Chaplet parity contract

This file enumerates the user-visible contract against which both plugins are
measured.  It is the acceptance oracle for later work: cite a stable section
name (for example, `PARITY 3 — Read surface`) rather than copying its text.
Sections are deliberately numbered and append-only in intent so citations do
not rot.  Each table row cites the Emacs symbol from which it was extracted.

## 1. Entry points

| Surface | Contract | Source |
| --- | --- | --- |
| `M-x chaplet` | Opens the bead browser on the `inbox` view. | `emacs/chaplet.el:chaplet` |
| `M-x chaplet-graph` | Opens the dependency graph; optional `view` selects its graph view. | `emacs/chaplet-graph.el:chaplet-graph` |
| `M-x chaplet-mode` | Global minor mode owning the global prefix map. | `emacs/chaplet.el:chaplet-mode` |
| `C-c b b` | Global `chaplet-mode` prefix binding for `chaplet`; therefore opens `inbox`. | `emacs/chaplet.el:chaplet-mode-map` |
| `C-c b s` | Global `chaplet-mode` prefix binding for `chaplet-graph`. | `emacs/chaplet.el:chaplet-mode-map` |

## 2. Views

`chaplet-bd--views` is the canonical view-symbol to filter-alist mapping.
`chaplet-bd--view-filters` returns its alist lookup result, therefore `nil`
for an unknown view.  `chaplet-bd--view-names` preserves this declaration
order: `inbox`, `human`, `deferred`, `open`, `in-progress`, `blocked`,
`closed`, `all`.  Sources: `emacs/chaplet-bd.el:chaplet-bd--views`,
`emacs/chaplet-bd.el:chaplet-bd--view-filters`, and
`emacs/chaplet-bd.el:chaplet-bd--view-names`.

| View | Exact filters alist | Source |
| --- | --- | --- |
| `inbox` | `((:status . "deferred"))` | `emacs/chaplet-bd.el:chaplet-bd--views` |
| `human` | `((:label . chaplet-human-label))`, where `chaplet-human-label` is `"human"` | `emacs/chaplet-bd.el:chaplet-bd--views` |
| `deferred` | `((:status . "deferred"))` | `emacs/chaplet-bd.el:chaplet-bd--views` |
| `open` | `((:status . "open"))` | `emacs/chaplet-bd.el:chaplet-bd--views` |
| `in-progress` | `((:status . "in_progress"))` | `emacs/chaplet-bd.el:chaplet-bd--views` |
| `blocked` | `((:status . "blocked"))` | `emacs/chaplet-bd.el:chaplet-bd--views` |
| `closed` | `((:status . "closed"))` | `emacs/chaplet-bd.el:chaplet-bd--views` |
| `all` | `((:all . t))` | `emacs/chaplet-bd.el:chaplet-bd--views` |

## 3. Read surface

Every bridge invocation is scoped as `bd -C <root> <argv>`, where `<root>` is
the current project root or `default-directory` fallback.  Invocation returns
`(exit . stdout)` and discards stderr.  Reads consume stdout only when exit is
zero; otherwise they return `nil`.  Source:
`emacs/chaplet-bd.el:chaplet-bd--root` and
`emacs/chaplet-bd.el:chaplet-bd--invoke`.

| Function | argv after `-C <root>` | Result | Source |
| --- | --- | --- | --- |
| `chaplet-bd-list` | `list --json` plus filter args | Normalized bead alists | `emacs/chaplet-bd.el:chaplet-bd-list` |
| `chaplet-bd-query` | `query --json <expr>` | Normalized bead alists | `emacs/chaplet-bd.el:chaplet-bd-query` |
| `chaplet-bd-show` | `show --json --long <id>` | One normalized bead alist | `emacs/chaplet-bd.el:chaplet-bd-show` |
| `chaplet-bd-comments` | `comments <id> --json` | Parsed comment alists | `emacs/chaplet-bd.el:chaplet-bd-comments` |
| `chaplet-bd-graph-dot` | With `(:id . <id>)`: `graph --dot <id>`; with `(:closed . t)`: `list --format dot --all`; otherwise: `graph --dot --all` | Raw DOT stdout | `emacs/chaplet-bd.el:chaplet-bd-graph-dot` |
| `chaplet-bd-graph-data` | Delegates to `chaplet-bd-list` with `<filters>` | Normalized bead alists | `emacs/chaplet-bd.el:chaplet-bd-graph-data` |

### Filter encodings

`chaplet-bd--filters->args` maps `:status`, `:type`, `:priority`, `:label`,
and `:limit` to `--status=<value>`, `--type=<value>`, `--priority=<value>`,
`--label=<value>`, and `--limit=<value>`.  Non-nil `:all`, `:ready`, and
`:deferred` emit bare `--all`, `--ready`, and `--deferred`; false boolean
values emit nothing.  Unknown filters signal an error.  Source:
`emacs/chaplet-bd.el:chaplet-bd--filters->args`.

`chaplet-bd--filters->expr` instead maps `:status`, `:type`, `:label`, and
`:priority` to `status=<value>`, `type=<value>`, `label=<value>`, and
`priority=<value>`, joining clauses with ` AND `.  It skips `:all`, `:ready`,
and `:deferred` regardless of value; unknown filters signal an error.  Source:
`emacs/chaplet-bd.el:chaplet-bd--filters->expr`.

## 4. Write surface

All write wrappers invoke through `chaplet-bd--invoke`.  A nil identifier (or
any non-string argv member) is rejected before process invocation with a
`user-error`.  The ordinary write helper reports `t` exactly for exit status
zero and `nil` otherwise; it does not inspect stdout.  `chaplet-bd-create` is
the exception in return shape: on status zero it returns trimmed stdout as the
new id, otherwise `nil`.  Sources: `emacs/chaplet-bd.el:chaplet-bd--invoke`,
`emacs/chaplet-bd.el:chaplet-bd--ok`, and
`emacs/chaplet-bd.el:chaplet-bd-create`.

| Wrapper | argv after `-C <root>` | Source |
| --- | --- | --- |
| `chaplet-bd-create` | `create <title> -t <type> -d <description> --silent` | `emacs/chaplet-bd.el:chaplet-bd-create` |
| `chaplet-bd-comment` | `comment <id> <text>` | `emacs/chaplet-bd.el:chaplet-bd-comment` |
| `chaplet-bd-undefer` | `undefer <id>` | `emacs/chaplet-bd.el:chaplet-bd-undefer` |
| `chaplet-bd-defer` | `defer <id>` | `emacs/chaplet-bd.el:chaplet-bd-defer` |
| `chaplet-bd-update` | `update <id> <flag> <value>`; `title` → `--title`, `description` → `--description`, `type` → `--type`, `design` → `--design`, `acceptance` → `--acceptance` | `emacs/chaplet-bd.el:chaplet-bd-update` |
| `chaplet-bd-update-design` | `update <id> --design <design>` | `emacs/chaplet-bd.el:chaplet-bd-update-design` |
| `chaplet-bd-update-acceptance` | `update <id> --acceptance <acceptance>` | `emacs/chaplet-bd.el:chaplet-bd-update-acceptance` |
| `chaplet-bd-label` | `label add <id> <label>` | `emacs/chaplet-bd.el:chaplet-bd-label` |
| `chaplet-bd-label-remove` | `label remove <id> <label>` | `emacs/chaplet-bd.el:chaplet-bd-label-remove` |
| `chaplet-bd-close` | `close <id>`; append `--reason <reason>` only for non-empty reason | `emacs/chaplet-bd.el:chaplet-bd-close` |
| `chaplet-bd-reopen` | `reopen <id>`; append `--reason <reason>` only for non-empty reason | `emacs/chaplet-bd.el:chaplet-bd-reopen` |
| `chaplet-bd-claim` | `update <id> --claim` | `emacs/chaplet-bd.el:chaplet-bd-claim` |
| `chaplet-bd-assign` | `assign <id> <assignee>`; empty assignee unassigns | `emacs/chaplet-bd.el:chaplet-bd-assign` |
| `chaplet-bd-priority` | `priority <id> <priority>` | `emacs/chaplet-bd.el:chaplet-bd-priority` |
| `chaplet-bd-dependency-add` | `dep add <id> <depends-on>` | `emacs/chaplet-bd.el:chaplet-bd-dependency-add` |
| `chaplet-bd-dependency-remove` | `dep remove <id> <depends-on>` | `emacs/chaplet-bd.el:chaplet-bd-dependency-remove` |
| `chaplet-bd-duplicate` | `duplicate <id> --of <canonical>` | `emacs/chaplet-bd.el:chaplet-bd-duplicate` |
| `chaplet-bd-supersede` | `supersede <id> --with <replacement>` | `emacs/chaplet-bd.el:chaplet-bd-supersede` |
| `chaplet-bd-human-respond` | `human respond <id> --response <response>` | `emacs/chaplet-bd.el:chaplet-bd-human-respond` |
| `chaplet-bd-human-dismiss` | `human dismiss <id>`; append `--reason <reason>` only for non-empty reason | `emacs/chaplet-bd.el:chaplet-bd-human-dismiss` |

## 5. JSON normalization

| Rule | Contract | Source |
| --- | --- | --- |
| Fields | Every normalized bead contains, in order, `id`, `title`, `description`, `status`, `priority`, `issue_type`, `owner`, `labels`, `dependencies`, `defer_until`, `design`, `acceptance`, `created_at`, `updated_at`, and `parent`. Missing source fields are `nil`. | `emacs/chaplet-bd.el:chaplet-bd--fields` and `emacs/chaplet-bd.el:chaplet-bd--normalize` |
| Acceptance fallback | If normalized `acceptance` is nil and JSON has `acceptance_criteria`, use that value as `acceptance`. | `emacs/chaplet-bd.el:chaplet-bd--normalize` |
| Dependencies | For dependency objects, replace each object with its `depends_on_id`; plain id strings pass through unchanged. | `emacs/chaplet-bd.el:chaplet-bd--normalize-deps` |
| JSON forms | Empty stdout and `null` parse as nil; an array parses as a list; a bare object becomes a one-item list. | `emacs/chaplet-bd.el:chaplet-bd--parse` |
| Parse failure | `json-parse-string` errors are not caught, so they surface to the caller. | `emacs/chaplet-bd.el:chaplet-bd--parse` |

## 6. List view

The sortable `tabulated-list` table has columns, in this order, `ID`, `Type`,
`State`, `P`, `Staged`, and `Title`.  Each row carries its bead id; ID, type,
and state use their corresponding faces.  Source:
`emacs/chaplet-list.el:chaplet-list--format` and
`emacs/chaplet-list.el:chaplet-list--entry`.

| Surface | Contract | Source |
| --- | --- | --- |
| Priority cell | Nil priority renders `""`; otherwise priority is coerced to a number and renders `●<n>` for `n >= 2`, `·<n>` for lower values, using that priority's face. | `emacs/chaplet-list.el:chaplet-list--priority-dot` |
| Staged cell | Renders a staged-face `✔` exactly when `chaplet-list--staged-p` is non-nil; otherwise `""`. | `emacs/chaplet-list.el:chaplet-list--entry` |
| Staged predicate | A bead is staged exactly when status is `"deferred"` **and** its labels contain `chaplet-staged-label`; the label alone is insufficient. | `emacs/chaplet-list.el:chaplet-list--staged-p` |
| Epic grouping | An epic header precedes its children; every child whose `parent` equals the epic id has its title indented by two spaces. Parentless non-epics follow grouped entries. | `emacs/chaplet-list.el:chaplet-list--group-by-epic` and `emacs/chaplet-list.el:chaplet-list--entry` |
| Out-of-view parent | When a child references a parent absent from the current result, fetch that parent with `chaplet-bd-show`, cache even a nil result by epic id, and insert it as the group header when present. | `emacs/chaplet-list.el:chaplet-list--fetch-epic` and `emacs/chaplet-list.el:chaplet-list--group-by-epic` |
| `RET` / `mouse-1` | Open bead at point through `chaplet-list-open`, preferring `chaplet-detail`; error when no row supplies an id. | `emacs/chaplet-list.el:chaplet-list-open` and `emacs/chaplet-list.el:chaplet-list--bind` |
| `v` | Select and render a named list view in the shared list buffer. | `emacs/chaplet-list.el:chaplet-list-set-view` |
| `s` | Open graph for the current list view. | `emacs/chaplet-list.el:chaplet-list-graph` |
| `?` | Open the state-aware action transient. | `emacs/chaplet-transient.el:chaplet-transient` |
| `q` | Quit the list window. | `emacs/chaplet-list.el:chaplet-list--bind` |

## 7. Action menu

The transient captures id, status, stagedness, and whether labels contain
`chaplet-human-label` when opened.  “Any” below means every status, including
`closed`; “not closed” means `status != "closed"`, which also includes a nil
captured status.  Unless noted, entries neither require stagedness nor the
`human` label.  Duplicate and supersede are the only entries that ask for a
confirmation (`y-or-n-p`) before invoking their write wrapper.  Sources:
`emacs/chaplet-transient.el:chaplet-transient` and
`emacs/chaplet-transient.el:chaplet-transient--actions-for-state`.

| Key | Entry and write wrapper | Visibility predicate | Confirmation | Source |
| --- | --- | --- | --- | --- |
| `a` | Approve: `chaplet-approve` calls `chaplet-bd-undefer`, then `chaplet-bd-label-remove` for `chaplet-staged-label`. | `status = "deferred"`; staged not required; human irrelevant. | No | `emacs/chaplet-transient.el:chaplet-approve`; `emacs/chaplet-bd.el:chaplet-bd-undefer`; `emacs/chaplet-bd.el:chaplet-bd-label-remove` |
| `r` | Reject: `chaplet-reject` writes `rejected: <feedback>` through `chaplet-bd-comment`; it does not undefer. | `status = "deferred"` and staged; human irrelevant. | No | `emacs/chaplet-transient.el:chaplet-reject`; `emacs/chaplet-bd.el:chaplet-bd-comment` |
| `C` | Claim: `chaplet-claim` → `chaplet-bd-claim`. | Not closed; staged and human irrelevant. | No | `emacs/chaplet-transient.el:chaplet-claim`; `emacs/chaplet-bd.el:chaplet-bd-claim` |
| `A` | Assign or blank-unassign: `chaplet-assign` → `chaplet-bd-assign`. | Any; staged and human irrelevant. | No | `emacs/chaplet-transient.el:chaplet-assign`; `emacs/chaplet-bd.el:chaplet-bd-assign` |
| `x` | Close with optional reason: `chaplet-close` → `chaplet-bd-close`. | Not closed; staged and human irrelevant. | No | `emacs/chaplet-transient.el:chaplet-close`; `emacs/chaplet-bd.el:chaplet-bd-close` |
| `o` | Reopen with optional reason: `chaplet-reopen` → `chaplet-bd-reopen`. | `status = "closed"`; staged and human irrelevant. | No | `emacs/chaplet-transient.el:chaplet-reopen`; `emacs/chaplet-bd.el:chaplet-bd-reopen` |
| `=` | Mark duplicate: `chaplet-duplicate` → `chaplet-bd-duplicate` with prompted canonical id. | Not closed; staged and human irrelevant. | Yes | `emacs/chaplet-transient.el:chaplet-duplicate`; `emacs/chaplet-bd.el:chaplet-bd-duplicate` |
| `S` | Supersede: `chaplet-supersede` → `chaplet-bd-supersede` with prompted replacement id. | Not closed; staged and human irrelevant. | Yes | `emacs/chaplet-transient.el:chaplet-supersede`; `emacs/chaplet-bd.el:chaplet-bd-supersede` |
| `c` | Comment: `chaplet-comment` → `chaplet-bd-comment`. | Any; staged and human irrelevant. | No | `emacs/chaplet-transient.el:chaplet-comment`; `emacs/chaplet-bd.el:chaplet-bd-comment` |
| `e` | Edit design: `chaplet-edit-design` → `chaplet-bd-update-design`. | Any; staged and human irrelevant. | No | `emacs/chaplet-transient.el:chaplet-edit-design`; `emacs/chaplet-bd.el:chaplet-bd-update-design` |
| `E` | Edit core field (`title`, `description`, `type`, `design`, or `acceptance`): `chaplet-edit-field` → `chaplet-bd-update`. | Any; staged and human irrelevant. | No | `emacs/chaplet-transient.el:chaplet-edit-field`; `emacs/chaplet-bd.el:chaplet-bd-update` |
| `p` | Set priority `0`–`4`: `chaplet-set-priority` → `chaplet-bd-priority`. | Any; staged and human irrelevant. | No | `emacs/chaplet-transient.el:chaplet-set-priority`; `emacs/chaplet-bd.el:chaplet-bd-priority` |
| `l` | Add label: `chaplet-add-label` → `chaplet-bd-label`. | Any; staged and human irrelevant. | No | `emacs/chaplet-transient.el:chaplet-add-label`; `emacs/chaplet-bd.el:chaplet-bd-label` |
| `L` | Remove label: `chaplet-remove-label` → `chaplet-bd-label-remove`. | Any; staged and human irrelevant. | No | `emacs/chaplet-transient.el:chaplet-remove-label`; `emacs/chaplet-bd.el:chaplet-bd-label-remove` |
| `d` | Add dependency: `chaplet-add-dependency` → `chaplet-bd-dependency-add`. | Any; staged and human irrelevant. | No | `emacs/chaplet-transient.el:chaplet-add-dependency`; `emacs/chaplet-bd.el:chaplet-bd-dependency-add` |
| `D` | Remove dependency: `chaplet-remove-dependency` → `chaplet-bd-dependency-remove`. | Any; staged and human irrelevant. | No | `emacs/chaplet-transient.el:chaplet-remove-dependency`; `emacs/chaplet-bd.el:chaplet-bd-dependency-remove` |
| `f` | Defer: `chaplet-defer` → `chaplet-bd-defer`. | Not closed; staged and human irrelevant. | No | `emacs/chaplet-transient.el:chaplet-defer`; `emacs/chaplet-bd.el:chaplet-bd-defer` |
| `h` | Respond + close: `chaplet-human-respond` → `chaplet-bd-human-respond`. | Has `human` label; every status and either stagedness. | No | `emacs/chaplet-transient.el:chaplet-human-respond`; `emacs/chaplet-bd.el:chaplet-bd-human-respond` |
| `H` | Dismiss: `chaplet-human-dismiss` → `chaplet-bd-human-dismiss`. | Has `human` label; every status and either stagedness. | No | `emacs/chaplet-transient.el:chaplet-human-dismiss`; `emacs/chaplet-bd.el:chaplet-bd-human-dismiss` |
| `n` | New bead: `chaplet-new` → `chaplet-bd-create`. | Any; staged and human irrelevant. | No | `emacs/chaplet-transient.el:chaplet-new`; `emacs/chaplet-bd.el:chaplet-bd-create` |
| `g` | Refresh every live Chaplet view: `chaplet-refresh` → `chaplet-refresh-all`. | Always; no status, staged, or human predicate. | No | `emacs/chaplet-transient.el:chaplet-refresh`; `emacs/chaplet-list.el:chaplet-refresh-all` |
| `v` | Switch list view: `chaplet-list-set-view`. | Always; no status, staged, or human predicate. | No | `emacs/chaplet-list.el:chaplet-list-set-view` |
| `s` | Open graph for current list view: `chaplet-list-graph`. | Only when `chaplet-list-graph` is bound; no status, staged, or human predicate. | No | `emacs/chaplet-transient.el:chaplet-transient`; `emacs/chaplet-list.el:chaplet-list-graph` |

Every successful action implementation above refreshes all Chaplet views;
the menu's `g` does so directly.  Source:
`emacs/chaplet-transient.el:chaplet-transient--refresh`.

## 8. Detail view

The shared, read-only detail buffer renders a markdown header first, then
non-empty sections in this fixed order: Description, Design, Acceptance,
Comments.  The header contains title, id, status, priority, type, owner,
created time, and labels when present.  Empty named sections are omitted.
Source: `emacs/chaplet-detail.el:chaplet-detail--render-header`,
`emacs/chaplet-detail.el:chaplet-detail--render`, and
`emacs/chaplet-detail.el:chaplet-detail`.

`chaplet-detail--activate-major-mode` enables `markdown-mode` when available;
otherwise it enables `fundamental-mode` plus `font-lock-mode`.  Source:
`emacs/chaplet-detail.el:chaplet-detail--activate-major-mode`.

| Key | Contract and condition | Source |
| --- | --- | --- |
| `q` | Quit detail window; no bead-state condition. | `emacs/chaplet-detail.el:chaplet-detail-quit` |
| `g` | Re-fetch and render current id when one exists; no bead-state condition. | `emacs/chaplet-detail.el:chaplet-detail-refresh` |
| `c` | Delegate comment to `chaplet-transient-comment` when available, otherwise report it unwired; no bead-state condition. | `emacs/chaplet-detail.el:chaplet-detail-comment` |
| `a` | Approve only a deferred bead; otherwise signal a user error. | `emacs/chaplet-detail.el:chaplet-detail-approve` |
| `r` | Reject only a deferred staged bead; otherwise signal a user error. | `emacs/chaplet-detail.el:chaplet-detail-reject` and `emacs/chaplet-detail.el:chaplet-detail--staged-p` |

## 9. Graph view

The graph is a deterministic layered, top-down DAG.  Dependency roots occupy
layer zero; a dependent is one layer below the greatest layer of its
dependencies.  Rows sort nodes by id, and arrows represent `(FROM . TO)` where
FROM depends on TO.  Unknown dependencies become closed ghost nodes.  Source:
`emacs/chaplet-graph.el:chaplet-graph--layers`,
`emacs/chaplet-graph.el:chaplet-graph--rows`, and
`emacs/chaplet-graph.el:chaplet-graph--layout`.

SVG nodes display id and title; title is truncated to
`chaplet-graph--title-max` columns with `…`.  State controls node color, and
staged deferred nodes use the staged color.  A focused node receives a halo.
Source: `emacs/chaplet-graph.el:chaplet-graph--node`,
`emacs/chaplet-graph.el:chaplet-graph--truncate`, and
`emacs/chaplet-graph.el:chaplet-graph--draw-node`.

| Key or event | Contract | Source |
| --- | --- | --- |
| `n` / `p` | Cycle focus forward / backward through node order. | `emacs/chaplet-graph.el:chaplet-graph--focus-next` and `emacs/chaplet-graph.el:chaplet-graph--focus-prev` |
| `RET` | Open focused node in detail; report no focused node otherwise. | `emacs/chaplet-graph.el:chaplet-graph--open-focused` |
| `d` | Move focus to a dependent of focused node; report when none. | `emacs/chaplet-graph.el:chaplet-graph--jump-dependents` |
| `f` | Move focus to a dependency of focused node; report when none. | `emacs/chaplet-graph.el:chaplet-graph--jump-deps` |
| `g` | Re-fetch graph data, preserving focus only when its node remains. | `emacs/chaplet-graph.el:chaplet-graph--refresh` |
| `c` | No graph binding exists; this source does not implement a closed-node toggle. | `emacs/chaplet-graph.el:chaplet-graph--bind` |
| `q` | Quit graph window. | `emacs/chaplet-graph.el:chaplet-graph--bind` |
| `mouse-1` | Open clicked node in detail. | `emacs/chaplet-graph.el:chaplet-graph--open-node` |
| `mouse-2` | Focus clicked node, then jump to its dependents. | `emacs/chaplet-graph.el:chaplet-graph--node-dependents` |

When inline SVG images are unavailable (including no display or no
`svg-image` result), render a navigable ASCII gutter-tree instead.  It has
one node per line; `│`, `└`, `┐`, and `─` thread concurrent dependency lanes.
Text node lines contain focus marker, id, title, state, and ghost marker; the
same navigation keys remain active.  Source:
`emacs/chaplet-graph.el:chaplet-graph--image-available-p`,
`emacs/chaplet-graph.el:chaplet-graph--text-gutter`, and
`emacs/chaplet-graph.el:chaplet-graph--text-render`.

| Tunable | Default | Contract | Source |
| --- | ---: | --- | --- |
| `chaplet-graph--x-gap` | 28 | Horizontal node gap, px. | `emacs/chaplet-graph.el:chaplet-graph--x-gap` |
| `chaplet-graph--y-gap` | 40 | Vertical layer gap, px. | `emacs/chaplet-graph.el:chaplet-graph--y-gap` |
| `chaplet-graph--node-h` | 28 | Node height, px. | `emacs/chaplet-graph.el:chaplet-graph--node-h` |
| `chaplet-graph--title-max` | 28 | SVG title width before truncation, columns. | `emacs/chaplet-graph.el:chaplet-graph--title-max` |
| `chaplet-graph--pad` | 8 | Node horizontal padding, px. | `emacs/chaplet-graph.el:chaplet-graph--pad` |
| `chaplet-graph--margin` | 16 | Canvas margin, px. | `emacs/chaplet-graph.el:chaplet-graph--margin` |
| `chaplet-graph--text-title-max` | 20 | ASCII title width before truncation, columns. | `emacs/chaplet-graph.el:chaplet-graph--text-title-max` |
| `chaplet-graph--text-align` | `nil` | Right-pad gutters to align node boxes. | `emacs/chaplet-graph.el:chaplet-graph--text-align` |
| `chaplet-graph--text-lane-max` | `nil` | Maximum ASCII gutter lanes; nil is unlimited. | `emacs/chaplet-graph.el:chaplet-graph--text-lane-max` |

## 10. Refresh and bindings

`chaplet-auto-refresh` defaults to `t`.  When non-nil, a list, detail, or
graph buffer runs its buffer-local show hook: it starts the periodic timer and
re-fetches only if it has never fetched or its last fetch is older than
`chaplet-refresh-delay`.  The delay defaults to `2` seconds and prevents a
fresh explicit fetch from being repeated by the show hook.  Source:
`emacs/chaplet-list.el:chaplet-auto-refresh`,
`emacs/chaplet-list.el:chaplet--refresh-on-focus`, and
`emacs/chaplet-list.el:chaplet--focus-stale-p`.

`chaplet-refresh-interval` defaults to `5` seconds.  A positive non-nil value
runs a repeating timer; `nil` disables timer ticks but retains show refreshes.
Each tick re-fetches only stale, visible non-minibuffer buffers and stops the
timer when no buffers are visible.  Source:
`emacs/chaplet-list.el:chaplet-refresh-interval`,
`emacs/chaplet-list.el:chaplet--ensure-refresh-timer`,
`emacs/chaplet-list.el:chaplet--visible-buffers`, and
`emacs/chaplet-list.el:chaplet--refresh-tick`.

Write actions call `chaplet-refresh-all` regardless of
`chaplet-auto-refresh`, refreshing the shared list plus every live detail and
graph buffer.  Source: `emacs/chaplet-list.el:chaplet-refresh-all` and
`emacs/chaplet-transient.el:chaplet-transient--refresh`.

### 10.1 Binding rule

Every buffer-local list, detail, and graph binding uses its module helper to
bind the plain mode map and, when Evil provides `evil-define-key*`, both Evil
normal and motion states.  This prevents read-only-buffer single-character
motions from leaking through: graph and detail are read-only, and their local
single-character commands remain available in both Evil states.  Source:
`emacs/chaplet-list.el:chaplet-list--bind`,
`emacs/chaplet-detail.el:chaplet-detail--bind`, and
`emacs/chaplet-graph.el:chaplet-graph--bind`.

### 10.2 Neovim foundation coverage

The Neovim column below records landed coverage for the foundation epic. Each
claim names the Lua symbol that implements it; the boundary spec at
`nvim/tests/boundary_spec.lua` enforces the single CLI spawn site.

| Surface | Contract | Emacs source | Neovim source |
| --- | --- | --- | --- |
| Entry points | `:Chaplet` opens the inbox, `:ChapletGraph` opens the graph, and the configured leader prefix binds their `b` and `s` commands. | `emacs/chaplet.el:chaplet`, `emacs/chaplet-graph.el:chaplet-graph`, `emacs/chaplet.el:chaplet-mode-map` | `nvim/lua/chaplet/init.lua:M.setup`; defaults in `nvim/lua/chaplet/config.lua:M.defaults` |
| Views | Eight views, in order: `inbox`, `human`, `deferred`, `open`, `in-progress`, `blocked`, `closed`, `all`; each has its canonical filter. | `emacs/chaplet-bd.el:chaplet-bd--views`, `chaplet-bd--view-names`, `chaplet-bd--view-filters` | `nvim/lua/chaplet/bd.lua:M.views`, `M.view_names`, `M.view_filters` |
| Filter translators | Argument and query-expression translators cover value filters, boolean filters, ordering, and unknown-filter rejection. | `emacs/chaplet-bd.el:chaplet-bd--filters->args`, `chaplet-bd--filters->expr` | `nvim/lua/chaplet/bd.lua:M.filters_to_args`, `M.filters_to_expr` |
| Read surface | `list`, `query`, `show --long`, comments, `graph --dot`, and `list --format dot --all` wrappers are covered. | `emacs/chaplet-bd.el:chaplet-bd-list`, `chaplet-bd-query`, `chaplet-bd-show`, `chaplet-bd-comments`, `chaplet-bd-graph-dot` | `nvim/lua/chaplet/bd.lua:M.list`, `M.query`, `M.show`, `M.comments`, `M.graph_dot` |
| Write surface: lifecycle | Create, comment, undefer, defer, update, labels, close, reopen, claim, assign, and priority wrappers are covered. | `emacs/chaplet-bd.el` write wrappers | `nvim/lua/chaplet/bd.lua:M.create`, `M.comment`, `M.undefer`, `M.defer`, `M.update`, `M.update_design`, `M.update_acceptance`, `M.label`, `M.label_remove`, `M.close`, `M.reopen`, `M.claim`, `M.assign`, `M.priority` |
| Write surface: relational and human | Dependency add/remove, duplicate, supersede, human respond, and human dismiss wrappers are covered. | `emacs/chaplet-bd.el` relational and human wrappers | `nvim/lua/chaplet/bd.lua:M.dependency_add`, `M.dependency_remove`, `M.duplicate`, `M.supersede`, `M.human_respond`, `M.human_dismiss` |
| Normalization | Normalized bead fields, `acceptance_criteria` fallback, and dependency-object flattening match the contract. The normalized bead table has **15 fields**, as defined by `chaplet-bd--fields` (not 16 as stated in the epic 2 description). | `emacs/chaplet-bd.el:chaplet-bd--fields`, `chaplet-bd--normalize`, `chaplet-bd--normalize-deps` | `nvim/lua/chaplet/bd.lua:M.FIELDS`, `M._normalize`, `M._normalize_deps` |
| Face and highlight palette | Dark/light state, priority, type, and staged colors share the canonical palette; state highlights blend with the active background and reapply on `ColorScheme`. | `emacs/chaplet-face.el:chaplet-face--dark-palette`, `chaplet-face--light-palette`, `chaplet-face-adapt` | `nvim/lua/chaplet/hl.lua:M.PALETTE`, `M.apply`, `M.setup` |

## 11. Sanctioned divergences

A plugin divergence is sanctioned only after it is recorded in this table.
Until then, PARITY behavior remains required.

| Plugin | PARITY section | Divergence | Rationale |
| --- | --- | --- | --- |
| Neovim | PARITY 3 — Read surface | The Neovim bridge is synchronous through one `M.invoke` choke point, matching the elisp `call-process` control flow. On Neovim 0.9, the bridge uses the `vim.fn.system` fallback path when `vim.system` is unavailable. | Async is a known performance divergence to revisit, not a parity break (epic D2). |
