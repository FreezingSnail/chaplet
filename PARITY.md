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
