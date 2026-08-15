# chaplet-uvy.1 — chaplet-face.el: theme-adaptive face module

## Interfaces implemented (chaplet-face.el)

| Symbol | Kind | Contract |
|---|---|---|
| `(chaplet-face-dark-p)` | fn → bool | Non-nil when `default` face background luminance < 0.5. Nil/unspecified bg counts light. |
| `(chaplet-face-adapt)` | fn → void | `face-spec-set` every palette face from active dark/light palette. State faces: fg + dim bg + `:box t` (pill). Priority/type/staged: fg only. Idempotent, batch-safe. |
| `(chaplet-face-setup)` | fn → void | Adapt + `(add-hook 'after-load-theme-hook #'chaplet-face-adapt)` (once). |
| `(chaplet-state-face status)` | fn → face \| nil | deferred→`chaplet-state-deferred`, in_progress→`-in-progress`, blocked→`-blocked`, closed→`-closed`, open→`-open`, else nil. |
| `(chaplet-state-color status)` | fn → string \| nil | Effective `:foreground` of state face via `face-attribute` (SVG fill); falls back to dark palette color when face unset. |
| `(chaplet-priority-face p)` | fn → face \| nil | 2→high, 1→medium, 0→low (number or numeric string), else nil. |
| `(chaplet-type-face type)` | fn → face \| nil | task/epic/bug → type faces, else nil. |

Deffaces (14): `chaplet-state-{deferred,in-progress,blocked,closed,open}`, `chaplet-priority-{high,medium,low}`, `chaplet-type-{epic,task,bug}`, `chaplet-header`, `chaplet-staged`, `chaplet-id`. Defaults = dark palette (per design §4.1).

Palettes: `chaplet-face--dark-palette`, `chaplet-face--light-palette` (defconst alists, 12 entries each). Dim pill background derived by `color-mix` (18% fg into default bg); state-face membership via `chaplet-face--state-faces`.

## Tests (chaplet-test.el, ERT)

Added 10 `chaplet-test-face-*` tests: dark-p dark/light, adapt re-specs every palette face + idempotent, state-face mapping (5 states + unknown/nil), state-color mirrors face-attribute, state-color fallback to dark palette, priority-face mapping (incl. numeric string), type-face mapping, setup hook registered once, all deffaces defined.

## Verification

```
emacs -Q --batch -L . -f batch-byte-compile chaplet-face.el   # exit 0, no warnings
emacs -Q --batch -L . -l chaplet-test --eval '(ert-run-tests-batch-and-exit "chaplet-test-")'
```

Result: **Ran 69 tests, 69 results as expected, 0 unexpected** (10 new + 59 pre-existing regression).

## Notes / deviations

- No deviations from design §4.1/§7.1. Dim pill background computed via `color-mix` (fg 18% into default bg) rather than hardcoded per-face bg — palette stays a single `(face . color)` alist per design.
- `defgroup chaplet` re-declared (also in chaplet-list.el) — duplicate group definition is allowed; will be unified when chaplet.el requires chaplet-face first (§4.5).
- `chaplet-list.el` keeps its own legacy fg-only deffaces for the same 4 state names until uvy.3; same face symbols, last-loaded spec wins. No test impact.

# chaplet-uvy.6 — chaplet.el: require chaplet-face + setup

## Changes

- `chaplet.el`: added `(require 'chaplet-face)` first in require chain — order now `chaplet-face` → `chaplet-bd` → `chaplet-list` → `chaplet-transient` → `chaplet-detail` → `chaplet-graph` (design §4.5). Added top-level `(chaplet-face-setup)` call after requires → applies theme-adaptive palette at load and registers `after-load-theme-hook` → `chaplet-face-adapt`.
- `chaplet-test.el`: new ERT `chaplet-test-entry-face-setup-on-load` — re-loads `chaplet.el` with `chaplet-face-setup` stubbed (cl-letf); asserts exactly one call at load. Requires short-circuit (deps already loaded), so only the top-level setup call executes.

## Defgroup reconciliation

Duplicate `defgroup chaplet` (chaplet-face.el + chaplet-list.el) confirmed benign: loading via `(require 'chaplet)` loads chaplet-face first (defines group), chaplet-list re-declaration is a no-op update. No errors.

## Verification

```
emacs -Q --batch -L . -f batch-byte-compile chaplet.el          # exit 0
emacs -Q --batch -L . --eval '(require (quote chaplet))'        # clean; chaplet-face loaded; after-load-theme-hook contains chaplet-face-adapt
emacs -Q --batch -L . -l chaplet-test --eval '(ert-run-tests-batch-and-exit "chaplet-test-")'
```

Result: **Ran 70 tests, 70 results as expected, 0 unexpected** (1 new + 69 regression).

## Notes / deviations

- Byte-compile emits pre-existing warning `chaplet.el:31:20: defcustom for chaplet-mode: fails to specify containing group` (untouched; `define-minor-mode` `:group` absent since before this task). No new warnings.
- `(chaplet-face-setup)` runs at load (top-level), not inside `chaplet-mode` activation, per design §4.5. Idempotent + batch-safe (face-spec-set only).

# chaplet-uvy.3 — chaplet-list.el: visual restyle

## Interfaces implemented (chaplet-list.el)

| Symbol | Kind | Contract |
|---|---|---|
| `(chaplet-list--priority-dot priority)` | fn → string | Priority cell: "●"/"·" dot + number, propertized with `chaplet-priority-face`; `""` when priority nil. ● = p≥2, · = p 0/1. |
| `(chaplet-list--modeline)` | fn → string | "chaplet `<view>` · `<n>` beads · `<o>` open · `<b>` blocked", counted from `tabulated-list-entries` (state = col 3). |
| `(chaplet-list--entry bead)` | fn → entry | Cells propertized: ID→`chaplet-id`, State→pill face (`chaplet-state-face` incl. open), P→priority dot+number, Type→`chaplet-type-face`, Staged→"✔" `chaplet-staged`. Public shape unchanged (id . [7-col vector]). |

Removed from chaplet-list.el: legacy `defgroup chaplet` + 4 duplicate state deffaces + `chaplet-list--state-face` (superseded by `chaplet-state-face` from chaplet-face.el).

## Buffer chrome (chaplet-list-mode)

- `(require 'chaplet-face)` + `(require 'cl-lib)`.
- `hl-line-mode 1` on entry.
- `mode-line-process = '(:eval (chaplet-list--modeline))`.
- Header face: `(face-remap-add-relative 'header-line '(chaplet-header header-line))` — buffer-local; persists across `tabulated-list-init-header` re-runs (sorting). Merges `chaplet-header` (bold) over `header-line` base. Note: Emacs 30.2 tabulated-list has no `tabulated-list-header` face (only `tabulated-list-fake-header` for the non-header-line path); header line face is `header-line`.
- `(define-key chaplet-list-mode-map [mouse-1] #'chaplet-list-open)` — shadows tabulated-list's `[mouse-1]` sort binding in the table body; `"<header-line> <mouse-1>"` sort binding still wins on the header row.
- `tabulated-list-padding` stays 2 (consistent with format widths; design §4.3).

## Tests (chaplet-test.el, ERT)

Added/updated 8 list tests: `chaplet-test-list-entry` + `-not-staged` (updated for propertized cells + "●2"/"·0" P column), `chaplet-test-list-entry-faces` (ID/state/priority/type/staged faces), `chaplet-test-list-priority-dot` (dot+face per priority), `chaplet-test-list-modeline` (view + counts), `chaplet-test-list-mouse-1` ([mouse-1] → open), `chaplet-test-list-buffer-style` (hl-line, mode-line-process, header face remap).

## Verification

```
emacs -Q --batch -L . -f batch-byte-compile chaplet-list.el chaplet-test.el   # exit 0, no warnings
emacs -Q --batch -L . -l chaplet-test --eval '(ert-run-tests-batch-and-exit "chaplet-test-")'
```

Result: **Ran 75 tests, 75 results as expected, 0 unexpected** (5 new + 2 updated + 68 regression).

## Notes / deviations

- Priority dot: ● for p≥2, · for p 0/1 (design specified "●" or "·" without exact split; chose filled dot for high).
- `chaplet-list--state-face` deleted — sole call site was `chaplet-list--entry`; module `chaplet-state-face` handles all 5 states incl. `open`.
- Header styling via `header-line` face remap rather than string-propertizing (survives sort re-init; matches Emacs 30.2 reality where `tabulated-list-header` face is absent).
- Byte-compile clean; no new warnings in chaplet-list.el. Note: prior uvy.6 note about `chaplet-mode` defcustom warning is in chaplet.el, untouched.

# chaplet-uvy.4 — chaplet-graph: pure layout + SVG pipeline

## Interfaces implemented (chaplet-graph.el, design §4.4)

| Symbol | Kind | Contract |
|---|---|---|
| `(chaplet-graph--nodes beads)` | fn → plists | bead alists → `(:id :title :state :type :priority :deps)`; title truncated to `chaplet-graph--title-max` (28) cols w/ ellipsis. |
| `(chaplet-graph--layout nodes)` | fn → `(nodes . edges)` | Layered top-down DAG. Layer = longest-path from roots; ghost deps depth 0. Per-layer id-stable sort. `w=max(min(title-width,28)*7+pad,90)`, `h=28`. x cumulative + x-gap, row centered on canvas midpoint; `y=margin+layer*(h+y-gap)`. Nodes gain `:x :y :w :h`. Edges `(FROM . TO)` — FROM depends on TO (arrow TO-ward). Ghost nodes appended for unknown deps (`:ghost t`, closed state, `" (closed)"` suffix). Deterministic, pure, headless-safe. |
| `(chaplet-graph--svg nodes edges focus-id)` | fn → svg DOM | `svg-create` + `svg-rectangle` (state-color fill via `chaplet-state-color`, id `node-<id>`), `svg-text` (id bold + title, white on fill), `svg-line` + `svg-polygon` arrowhead per edge (gray), focus halo = 3px stroke-width rect when `focus-id` matches. |
| `(chaplet-graph--svg-string svg)` | fn → string | `svg-print` into temp buffer. |
| `(chaplet-graph--image-map nodes)` | fn → `:map` alist | One `(AREA ID PLIST)` region per node; `AREA=(rect . ((x1 . y1) . (x2 . y2)))`, ID = interned node id (events `[ID mouse-1]`/`[ID mouse-2]`), PLIST `help-echo "id — title"`. |
| Helpers | fns | `chaplet-graph--truncate`, `--node`, `--ghost-node`, `--add-ghosts`, `--layers`, `--node-w`, `--row-width`, `--sort-by-id`, `--rows`, `--canvas-size`, `--node-color`, `--draw-node`, `--draw-edge`. |

Defcustoms (group `chaplet-graph`): `chaplet-graph--x-gap 28`, `--y-gap 40`, `--node-h 28`, `--title-max 28`, `--pad 8`, `--margin 16` (design §5.4).

Depends: `chaplet-bd` (graph-data), `chaplet-face` (`chaplet-state-color` fills), built-in `svg` + `dom`. Zero external deps. Existing Graphviz-based entry/render/mode kept intact (back-compat; uvy.5 rewrites buffer/nav/text-fallback).

## Tests (chaplet-test.el, ERT)

Added 12 `chaplet-test-graph-*`: nodes conversion, title truncation, layered ordering (roots top, ghost at root layer, y math), same-layer non-overlap + min width, ghost node (flag/suffix/closed/edge), determinism + empty input, svg elements (rect/text/line/polygon counts, node id, state fill), focus halo iff focus-id, svg string (contains `<svg`/node id/polygon), image-map regions (shape, coords, help-echo), image-map event dispatch (`[id mouse-1]`/`[id mouse-2]`).

## Verification

```
emacs -Q --batch -L . -f batch-byte-compile chaplet-graph.el   # exit 0, no warnings
emacs -Q --batch -L . -l chaplet-test --eval '(ert-run-tests-batch-and-exit "chaplet-test-")'
```

Result: **Ran 86 tests, 86 results as expected, 0 unexpected** (12 new + 74 pre-existing regression).

## Notes / deviations

- **Image map format**: design §7.4/Appendix C research note (`((rect (x1 . y1) (x2 . y2)) keymap)`) does not match Emacs 30.2 reality. Elisp manual "Image Descriptors" format is `(AREA ID PLIST)`; hot-spot clicks compose `[ID mouse-1]` events and regions carry `help-echo`/`pointer` only — no per-region keymap. Implemented per manual; region IDs interned to symbols so `[bd-1 mouse-1]` dispatch works in the graph keymap (uvy.5 binds those to open/dependents).
- Ghost deps counted at depth 0 → ghost nodes render at root layer (per task: "ghost deps treated as depth 0 + 1").
- Edge arrowheads drawn as `svg-polygon` triangles (svg.el has no marker/defs helper); "same-layer elbow" (§4.4 step 5) is a no-op — same-layer edges cannot occur in longest-path layering.
- `chaplet-graph--svg` returns the svg DOM object (design §4.4); string via `chaplet-graph--svg-string`.
- Buffer/nav/keys/text-fallback intentionally not in this task (uvy.5); old Graphviz entry path still live for existing tests.

# chaplet-uvy.5 — chaplet-graph: buffer, navigation, text fallback

## Interfaces implemented (chaplet-graph.el, design §4.4)

| Symbol | Kind | Contract |
|---|---|---|
| `(chaplet-graph &optional include-closed)` | cmd (interactive `"P"`) | Entry. C-u → closed. Creates `*chaplet:graph*`, sets buffer-local `chaplet-graph--include-closed`, `chaplet-graph--refresh`, `pop-to-buffer`. |
| `(chaplet-graph-mode)` | minor mode | Keymap `chaplet-graph-mode-map`: `n`→`chaplet-graph--focus-next`, `p`→`--focus-prev`, `RET`→`--open-focused`, `d`→`--jump-dependents`, `f`→`--jump-deps`, `g`→`--refresh`, `c`→`chaplet-graph-toggle-closed`, `q`→`quit-window`. |
| `(chaplet-graph--render nodes edges focus-id)` | fn → buffer | Erase + render current buffer. Image path: `svg-image` + `:map`, `insert-image`, `image-mode 1`. Fallback (no display or `svg-image` nil): `chaplet-graph--text-render`. Sets buffer-locals `chaplet-graph--nodes/--edges/--focus-id/--text-mode`; installs `[ID mouse-1]`/`[ID mouse-2]` bindings; mode-line. |
| `(chaplet-graph--refresh)` | cmd | Re-fetch `(chaplet-bd-graph-data include-closed)` → `--nodes` → `--layout` → `--render`. Preserves `chaplet-graph--focus-id` iff focused id still in new node set; else nil. `nil` beads → message, prior buffer kept (§6). |
| `(chaplet-graph--focus-next/-prev)` | cmds | `chaplet-graph--focus-relative ±1`: cycle over `chaplet-graph--nodes` order (input order + ghosts appended), re-render w/ focus halo. |
| `(chaplet-graph--open-focused)` | cmd | `(chaplet-detail chaplet-graph--focus-id)`; message when no focus. |
| `(chaplet-graph--jump-dependents)` / `(--jump-deps)` | cmds | `d`: focus first node with edge `(dep . focus)`; `f`: focus first `(focus . dep)` target. Re-render; message when none. |
| `(chaplet-graph-toggle-closed)` | cmd | Flip buffer-local include-closed, refresh. |
| `(chaplet-graph--text-render nodes edges focus-id)` | fn | Navigable outline: one line per node `▶/   ID title` (+ ` (ghost)` suffix), `↳ dep ID` lines; focus marker moves with n/p. Same keymap. |
| `(chaplet-graph--image-available-p)` | fn → bool | `(and (display-images-p) (fboundp 'svg-image))`. |
| `(chaplet-graph--bind-node-events nodes)` | fn | Replaces previous render's `[ID mouse-1]`→`chaplet-graph--open-node`, `[ID mouse-2]`→`chaplet-graph--node-dependents` in `chaplet-graph-mode-map`. |
| `(chaplet-graph--clicked-id)` | fn → sym \| nil | `(aref (this-command-keys-vector) 0)` of the `[ID mouse-N]` hot-spot key sequence. |
| Buffer-locals | vars | `chaplet-graph--nodes` (node plists w/ xywh), `--edges`, `--focus-id`, `--text-mode`, `--include-closed`. |

Removed: Graphviz path (`chaplet-graph-dot-program`, `--dot-available-p`, `--dot->svg`, `--show-dot`, raw-DOT fallback) per design Appendix A ("dot dropped").

## Tests (chaplet-test.el, ERT)

Added 8 `chaplet-test-graph-*` nav tests: `mode-map` (full key set n/p/RET/d/f/g/c/q), `focus-cycle` (next/prev + wrap + re-render, no-focus → first), `open-focused` (chaplet-detail called w/ id; no-op w/o focus), `jump` (d/f along edges w/ re-render), `text-fallback` (outline content, ▶ marker, ghost suffix, n moves marker), `refresh-preserves-focus` (graph-data forwarded, focus kept/dropped), `mouse-bindings` (`[ID mouse-1/2]` installed per node), `clicked-id` (id recovered from `this-command-keys-vector`).

Updated 6 legacy tests to the new pipeline (no longer Graphviz): `graph-render`, `headless-render`, `headless-fallback` (text outline, not raw DOT), `graph-include-closed` (stubs `chaplet-bd-graph-data`), `graph-toggle-closed`, `graph-refresh-closed` (forwards include-closed). Deleted `graph-dot-available-p` + `graph-dot->svg` (feature removed).

## Verification

```
emacs -Q --batch -L . -f batch-byte-compile chaplet-graph.el   # exit 0, no warnings
emacs -Q --batch -L . -l chaplet-test --eval '(ert-run-tests-batch-and-exit "chaplet-test-")'
```

Result: **Ran 91 tests, 91 results as expected, 0 unexpected** (8 new nav + 4 rewritten legacy + 12 uvy.4 pipeline + 67 regression). Full multi-file byte-compile: exit 0, only pre-existing warnings (chaplet.el `chaplet-mode` defcustom group; chaplet-detail `markdown-mode` declare).

## Notes / deviations

- Hot-spot click commands recover the node id from `(this-command-keys-vector)` — the `[ID mouse-N]` key sequence composed per the elisp manual — instead of an event arg; verified dispatch convention against Emacs 30.2 manual "Image Descriptors" + image.el source (`image--compute-map`).
- Node order for focus cycling = `chaplet-graph--layout` output order (input order with ghosts appended), not per-layer order; documented in `--focus-relative`.
- `chaplet-graph--text-render` keeps the design signature `(nodes edges focus-id)`; `edges` currently unused (dep lines come from `:deps`), silenced with `(ignore edges)`.
- Emacs `let` init forms cannot reference earlier bindings of the same `let` — used `let*` in `--text-render` (byte-compiler caught the original).
- `chaplet-graph-mode` now uses an explicit `defvar chaplet-graph-mode-map` (define-minor-mode skips map creation when `:keymap` is a symbol) so `--bind-node-events` can mutate it per render.
- Old Graphviz tests removed with the feature (design Appendix A drops `dot`); `test/fake-dot` left in place (harmless).

# chaplet-uvy.7 — Integration: docs, byte-compile, full test pass

## Final interface summary (epic complete)

### New module: chaplet-face.el (theme-adaptive faces + SVG colors)

| Symbol | Kind | Contract |
|---|---|---|
| `(chaplet-face-dark-p)` | fn → bool | Non-nil when `default` face bg luminance < 0.5; nil/unspecified = light. |
| `(chaplet-face-adapt)` | fn → void | `face-spec-set` every palette face from active dark/light palette. State faces: fg + dim bg (`color-mix` 18%) + `:box t`. Idempotent, batch-safe. |
| `(chaplet-face-setup)` | fn → void | Adapt + `after-load-theme-hook` → adapt (once). |
| `(chaplet-state-face status)` | fn → face \| nil | deferred/in_progress/blocked/closed/open → state faces. |
| `(chaplet-state-color status)` | fn → string \| nil | Effective state-face `:foreground` (SVG fill); dark-palette fallback when unset. |
| `(chaplet-priority-face p)` / `(chaplet-type-face t)` | fn → face \| nil | priority 2/1/0 (or numeric string); type task/epic/bug. |

14 deffaces; `chaplet-face--{dark,light}-palette` (12 entries each); `chaplet-face--state-faces`. Single palette source for list text + graph fills.

### chaplet-bd.el: `(chaplet-bd-graph-data &optional include-closed)`

fn → bead alist list. nil → `(chaplet-bd-list nil)` [open]; t → `(chaplet-bd-list '((:all . t)))` [all]. Beads carry `dependencies` (id strings). Legacy `chaplet-bd-graph-dot` retained unchanged (back-compat only; graph view no longer uses it).

### chaplet-list.el (restyle — public interface unchanged)

- `chaplet-list--priority-dot` — "●"/"·" + number, priority face; `""` when nil.
- `chaplet-list--modeline` — "chaplet `<view>` · `<n>` beads · `<o>` open · `<b>` blocked".
- `chaplet-list--entry` — cells propertized (ID→`chaplet-id`, State→pill, P→dot, Type→type face, Staged→"✔"); public `(id . [7-col])` shape unchanged.
- Buffer chrome: `hl-line-mode 1`, `mode-line-process`, `header-line` face remap, `[mouse-1]`→`chaplet-list-open`.
- Removed: legacy `defgroup`/duplicate state deffaces/`chaplet-list--state-face`.

### chaplet-graph.el (rewrite — pure pipeline + navigable buffer)

| Symbol | Kind | Contract |
|---|---|---|
| `(chaplet-graph &optional include-closed)` | cmd | Entry; C-u → closed. `*chaplet:graph*`, `chaplet-graph--refresh`, `pop-to-buffer`. |
| `(chaplet-graph-mode)` | minor mode | Keys: `n`/`p` focus next/prev, `RET` open focused, `d` dependents, `f` deps, `g` refresh, `c` toggle closed, `q` quit. Node hot-spots `[ID mouse-1]` (open) / `[ID mouse-2]` (dependents). |
| `(chaplet-graph--nodes beads)` | fn → plists | `(:id :title :state :type :priority :deps)`; title ≤ 28 cols. |
| `(chaplet-graph--layout nodes)` | fn → `(nodes . edges)` | Longest-path layered DAG; ghosts for unknown deps (depth 0); xywh per node; deterministic. |
| `(chaplet-graph--svg nodes edges focus-id)` | fn → svg DOM | State-color fills, arrowheads, 3px focus halo iff focus-id. |
| `(chaplet-graph--image-map nodes)` | fn → `:map` | `(rect coords ID help-echo)` per node. |
| `(chaplet-graph--render nodes edges focus-id)` | fn → buffer | SVG image + `:map`; text-outline fallback when no images. |
| `(chaplet-graph--text-render nodes edges focus-id)` | fn | Navigable outline (`▶` marker, ghost suffix, `↳ dep` lines), same keys. |

Removed: Graphviz path (`chaplet-graph-dot-program`, `--dot-available-p`, `--dot->svg`, `--show-dot`, raw-DOT fallback) — `dot` dropped per design Appendix A. Zero external deps.

## Files

NEW `chaplet-face.el`; MOD `chaplet-bd.el`, `chaplet-list.el`, `chaplet-graph.el` (rewrite), `chaplet.el` (require order + `(chaplet-face-setup)`), `chaplet-test.el`, `test/fake-bd` (dependencies fixture); MOD `output.md`. No README/docs present in repo — nothing to update.

## Verification (final, all modules)

```
emacs -Q --batch -L . -f batch-byte-compile chaplet-face.el chaplet-bd.el \
  chaplet-list.el chaplet-graph.el chaplet.el chaplet-detail.el \
  chaplet-transient.el chaplet-test.el
```

Exit 0. 2 pre-existing warnings unchanged: chaplet.el `chaplet-mode` defcustom group; chaplet-detail `markdown-mode` not-known. 0 new errors/warnings.

```
emacs -Q --batch -L . -l chaplet-test --eval '(ert-run-tests-batch-and-exit "chaplet-test-")'
```

**Ran 91 tests, 91 results as expected, 0 unexpected** (10 face + 3 graph-data + 8 list restyle + 12 layout/SVG + 8 nav + 50 regression/integration).

# chaplet-uvy.8 — Bottom keybinding bar in list + graph buffers

## Interfaces implemented (new module chaplet-bar.el)

| Symbol | Kind | Contract |
|---|---|---|
| `(chaplet-bar--install)` | fn → void | Append one `(:eval (chaplet-bar--render))` element to buffer-local `mode-line-format`. Idempotent: `chaplet-bar--installed` guard, at most once per buffer. |
| `(chaplet-bar--render)` | fn → string | Mode-line bar string for current buffer. Entries `"[KEY] LABEL"`, face `chaplet-bar`, joined `" "`, `""` when none. Reads buffer-locals `chaplet-bar--map`/`--specs`/`--extra`. |
| `(chaplet-bar--entries)` / `(--bound)` | fns | `--bound`: specs whose key (`kbd`-parsed) is bound in `chaplet-bar--map` via `lookup-key` (unbound keys omitted — bar always mirrors real keymap). `--entries`: bound specs + `--extra` static entries. |
| Buffer-locals | vars | `chaplet-bar--map` (keymap), `--specs` (alist KEY-STRING . LABEL), `--extra` (static, e.g. per-node mouse), `--installed` (guard). |

Depends: `chaplet-face` (face only). Built-in `kbd`/`lookup-key` — zero external deps.

Face: `chaplet-bar` defface in chaplet-face.el (`:inherit mode-line :weight bold`, group `chaplet`).

## Buffer integration

- `chaplet-list.el`: `(require 'chaplet-bar)`; defvar `chaplet-list--bar-specs`; mode body sets `chaplet-bar--map` → `chaplet-list-mode-map` + specs + install.
- `chaplet-graph.el`: `(require 'chaplet-bar)`; defvars `chaplet-graph--bar-specs` (keyboard) + `chaplet-graph--bar-extra` (mouse); `chaplet-graph--render` sets buffer-locals + installs (survives image-mode + repeated re-renders).
- `chaplet.el`: require chain `chaplet-face` → `chaplet-bar` → `chaplet-bd` → `chaplet-list` …

## Key list (derived from real keymaps)

- **Main (chaplet-list-mode-map)**: `v` view switch · `s` graph · `?` actions · `RET` open · `q` quit · `mouse-1` open.
- **Graph (chaplet-graph-mode-map)**: `n` next · `p` prev · `RET` open focused · `d` dependents · `f` deps · `g` refresh · `c` toggle closed · `q` quit · `mouse-1` open node · `mouse-2` dependents.

## Deviations from task key list

- Main `s` is **graph**, not "status toggle" (actual binding `chaplet-list--bind (kbd "s") #'chaplet-graph`).
- Main `c` **closed toggle is not bound** in chaplet-list-mode-map — omitted from the bar (task explicitly allowed adjusting to real bindings). Closed view reachable via `v` → view switch.
- Main bar additionally lists `?` (actions → `chaplet-transient`, bound at chaplet-transient.el:165) and `RET` (open) — both live bindings.
- Graph mouse entries are static extras (per-node hot-spots are `[ID mouse-1]`/`[ID mouse-2]`, not plain keys — not keymap-queryable).

## Tests (chaplet-test.el, ERT)

Added 6 `chaplet-test-bar-*`: `list-installed` (mode-line element + rendered keys), `graph-installed` (same after `--render`), `list-keys-match-keymap` (every listed key bound in list map; asserts `c` absent, `s` present), `graph-keys-match-keymap` (keyboard keys bound; mouse via installed `[ID mouse-1]` node binding), `unrelated-buffer` (no bar element/flag, render `""`), `idempotent` (double install → exactly 1 element). `chaplet-test-face-deffaces` updated to include `chaplet-bar`.

## Verification

```
emacs -Q --batch -L . -f batch-byte-compile chaplet-bar.el chaplet-face.el \
  chaplet-list.el chaplet-graph.el chaplet.el chaplet-test.el   # exit 0, no new warnings
emacs -Q --batch -L . -l chaplet-test --eval '(ert-run-tests-batch-and-exit "chaplet-test-")'
```

Result: **Ran 97 tests, 97 results as expected, 0 unexpected** (6 new + 91 regression). Byte-compile: exit 0, 0 new warnings (only pre-existing chaplet.el `chaplet-mode` defcustom-group warning).

