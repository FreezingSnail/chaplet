# chaplet-j0f.2 — rewrite + extend ASCII renderer tests

## What changed

`chaplet-test.el` only (renderer `chaplet-graph.el` untouched). Rewrote the 3
stale column-per-layer tests and added 6 gutter-tree fixtures, all asserting
on concrete gutter glyphs `│ └ ┐ ─` plus node box text.

### Rewritten

- **`chaplet-test-graph-text-columns`** — was `bd-3.*bd-2.*bd-1`. Now asserts
  topological node order (`bd-1, missing-dep, bd-2, bd-3`) via a line-order
  helper and the `└│`/`└┐` indentation glyphs.
- **`chaplet-test-graph-text-edges`** — was `──→` + `│`. Now renders a 2-dep
  merge (`a`, `b` roots → `c`) and asserts the `│` lane continuation on `b`'s
  line and the `└┐` merge bus on `c`'s line; asserts `──`/`→` are absent.
- **`chaplet-test-graph-text-fallback`** — swapped the `──→` assertion for
  `└┐` + `└│` gutter glyphs, kept `▶` focus and `~` ghost assertions.

### Added

- **`chaplet-test-graph-text-chain`** — a→b→c: each node once, `└` steps on
  `b`/`c`, no `┐`/`│`.
- **`chaplet-test-graph-text-fork`** — fan-out with continuing dependents
  (a→{b,c}, b→d, c→e): two lanes open, `└│` + `│└` branching.
- **`chaplet-test-graph-text-diamond`** — A←B, A←C, B+C←D: A once, `└` to B,
  `└│` threading to C, `└┐` merge on D.
- **`chaplet-test-graph-text-merge-bus`** — 3-dep node draws `└─┐` (`─` span)
  with `│`/`││` continuations above.
- **`chaplet-test-graph-text-width`** — every line
  `(string-width line) ≤ max-lanes + 1 + box-width` (max-lanes 3); fixture max
  line width `< 80` (actual 19).
- **`chaplet-test-graph-text-truncation-e2e`** — asserts
  `chaplet-graph--text-title-max` defaults to 20; a 40-char title renders as
  19 chars + `…` (not the full title).

### Helpers added

- `chaplet-test--text-canvas (beads &optional focus-id)` — pure string render
  (no buffer/display stub).
- `chaplet-test--text-node-ids (beads &optional focus-id)` — node ids in line
  order, extracted from `[id]` boxes.

## Verification

`./check.sh` → exit 0: 115/115 ERT pass, 0 unexpected, byte-compile clean, no
warnings. Focus/ghost/face/truncation assertions unchanged and still green.

## Notes

- Fork `┐` in the design §7 wording is a loose description; the renderer emits
  `┐` only on merges (covered by the diamond/merge-bus/edges tests). The fork
  test asserts the actual fan-out glyphs (`└│`/`│└`).
- Chain produces only `└` steps (no `│`), since each lane closes immediately
  after its single dependent prints.
