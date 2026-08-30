# chaplet

A magit-style Emacs interface for the [`bd`](https://github.com/gastownhall/beads)
(beads) issue tracker.

Browse your beads as a sortable, filterable table; inspect a dependency
graph as an inline SVG (with a `git log --graph`-style ASCII fallback);
approve, reject, comment, and edit beads through magit-like `transient`
menus — all with a persistent keybinding reference bar and
theme-adaptive faces (dark and light).

- Zero dependency on the tracker itself: it shells out to the `bd` CLI.
- Evil-aware bindings (plain Emacs + `evil` normal/motion states).
- Read-only buffers that suppress leaking single-char evil motions.
- Auto-updates as tickets change: write actions refresh every open view,
  and visible list, graph, and detail buffers re-fetch from `bd` when shown
  and every five seconds by default (see `chaplet-auto-refresh` and
  `chaplet-refresh-interval`).

## Repository layout

```text
emacs/       Emacs plugin, local harness, installer, and probes
nvim/        Neovim plugin tree placeholder
 test/       Shared test doubles and harness checks
check.sh     Root test dispatcher
install.sh   Root installation dispatcher
PARITY.md    Cross-plugin behavior contract
.beads/      Local Beads issue database
```

`PARITY.md` is the cross-plugin contract for user-visible behavior.

---

## Requirements

- **GNU Emacs** 28+ (uses `tabulated-list`, `svg`, `json`, `project`).
- [`bd`](https://github.com/gastownhall/beads) on your `PATH`.
- [`transient`](https://elpa.gnu.org/packages/transient.html) (menu popups).
- Optional: `markdown-mode` (nicer detail buffers), `evil`
  (normal/motion keybindings), `librsvg`/Emacs-with-SVG (graph images —
  otherwise the graph falls back to an ASCII gutter-tree).

## Installation

### `install.sh` (recommended)

```bash
./install.sh             # install all available plugins
./install.sh --emacs     # install the Emacs plugin
./install.sh --nvim      # select the Neovim plugin
./install.sh --uninstall
```

Users upgrading from before the restructure must run
`./install.sh --uninstall` and then install again, because the wired
`load-path` points at the old root.

Doom-aware: detects `~/.config/doom/config.el` and wires there,
otherwise `~/.emacs.d/init.el`. Idempotent (marker-based, re-run anytime).

### Manual

```elisp
(add-to-list 'load-path "/path/to/chaplet/emacs")
(require 'chaplet)
(chaplet-mode 1)
```

## Usage

| Command | Effect |
| --- | --- |
| `M-x chaplet` | Open the bead browser on the **inbox** (all deferred beads) view |
| `M-x chaplet-graph` | Open the dependency graph |
| `M-x chaplet-mode` | Global minor mode (enables the `C-c b` prefix) |

Global keys (with `chaplet-mode` on):

| Key | Effect |
| --- | --- |
| `C-c b b` | Open chaplet (inbox) |
| `C-c b s` | Open the graph |

### List view

The browser is a `tabulated-list` table of beads with a switchable view
and a live keybinding bar in the mode line.  When parent metadata is
available, epic beads are shown above their related tasks, which are
indented beneath them; an epic outside the current view is fetched so it
can still be displayed as the group header.

| Key | Effect |
| --- | --- |
| `RET` / `mouse-1` | Open bead detail |
| `v` | Switch view |
| `s` | Open graph |
| `?` | Action menu (transient) |
| `q` | Quit |

Views: `inbox` (status=deferred; all deferred work awaiting fleet pickup), `human` (label=human; requests requiring a human response), `deferred` (same deferred pool, for direct selection), `open`, `in-progress`, `blocked`, `closed`, `all` (unfiltered).

### Action menu (transient)

Pressing `?` over a bead opens a state-aware lifecycle popup. Approve moves
every deferred bead to open for fleet pickup; reject applies only to staged
review beads. Closed beads expose reopen. Every bead exposes comments, core-field editing,
claim/assign, priority and label updates, dependency management, and close
(or reopen). Duplicate/supersede close the current bead after confirmation.
Human-labelled beads additionally expose native `bd human respond` and
dismiss actions.

| Key | Effect |
| --- | --- |
| `a` | Approve (undefer) — every deferred bead |
| `r` | Reject (comment + stays staged) — staged review beads |
| `C` / `A` | Claim / assign |
| `x` / `o` | Close / reopen |
| `=` / `S` | Duplicate / supersede (confirmation) |
| `c` | Comment |
| `e` / `E` | Edit design / core field |
| `p` | Set priority |
| `l` / `L` | Add / remove label |
| `d` / `D` | Add / remove dependency |
| `f` | Defer |
| `h` / `H` | Human respond + close / dismiss — human-labelled beads |
| `n` | New bead |
| `g` | Refresh |
| `v` | Switch view |
| `s` | Graph |

### Graph view

A layered top-down DAG. SVG when image support is available, otherwise a
navigable ASCII gutter-tree (same keys).

| Key | Effect |
| --- | --- |
| `n` / `p` | Focus next / previous node |
| `RET` | Open focused bead |
| `d` / `f` | Jump to dependents / dependencies |
| `g` | Refresh |
| `c` | Toggle closed beads |
| `q` | Quit |
| `mouse-1` / `mouse-2` | Open node / show dependents |

### Detail view

| Key | Effect |
| --- | --- |
| `q` | Quit |
| `g` | Refresh |
| `c` | Comment |
| `a` | Approve — deferred beads |
| `r` | Reject — staged inbox beads |

## Configuration

```elisp
;; Graph layout (px)
(setq chaplet-graph--x-gap 28)     ; horizontal node gap
(setq chaplet-graph--y-gap 40)     ; vertical layer gap
(setq chaplet-graph--node-h 28)    ; node height
(setq chaplet-graph--title-max 28) ; title width before truncation
(setq chaplet-graph--pad 8)        ; node inner padding
(setq chaplet-graph--margin 16)    ; canvas margin

;; ASCII gutter-tree fallback
(setq chaplet-graph--text-title-max 20) ; title truncation width
(setq chaplet-graph--text-align nil)    ; right-pad gutters to align boxes
(setq chaplet-graph--text-lane-max nil) ; cap gutter lanes (nil = unlimited)

;; Auto-refresh (default t)
(setq chaplet-auto-refresh nil)         ; disable focus + periodic auto-refresh
(setq chaplet-refresh-interval 5)       ; seconds; nil disables periodic refresh
(setq chaplet-refresh-delay 2)          ; min seconds between focus refreshes
```

## Architecture

| File | Role |
| --- | --- |
| `emacs/chaplet.el` | Entry point, global minor mode + keymap |
| `emacs/chaplet-bd.el` | Sole `bd` CLI bridge (JSON reads, subcommand writes) |
| `emacs/chaplet-face.el` | Theme-adaptive faces + SVG colors (single palette) |
| `emacs/chaplet-list.el` | `tabulated-list` bead browser (views + filters) |
| `emacs/chaplet-transient.el` | State-aware action menus |
| `emacs/chaplet-detail.el` | Read-only markdown detail buffer |
| `emacs/chaplet-graph.el` | Dependency DAG → SVG (ASCII gutter-tree fallback) |
| `emacs/chaplet-bar.el` | Mode-line keybinding reference bar |
| `PARITY.md` | Cross-plugin user-visible behavior contract |
| `test/` | Shared test doubles and harness checks |
| `check.sh` | Root test dispatcher |
| `install.sh` | Root installation dispatcher |

## Development

```bash
./check.sh                         # shared checks + all available plugins
./check.sh emacs [args...]         # dispatch to the Emacs harness
./check.sh nvim [args...]          # dispatch to the Neovim harness
./check.sh emacs probe probes/x.el # run an exploratory Emacs probe
```

Run plugin-local commands from `emacs/` when working on the Emacs plugin:
`./check.sh probe probes/x.el`. Probes require a plugin selector at the root.
Exit codes: `0` green · `1` compile error · `2` test fail · `3` probe fail ·
`5` warnings. Tests are in `emacs/chaplet-test.el`; exploratory probes live in
`emacs/probes/` and are promoted by renaming `probe-*` → `chaplet-test-*`.
Shared harness checks run from `test/harness-test.sh`.
