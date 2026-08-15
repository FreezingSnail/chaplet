# chaplet-v08 — optional lane cap (chaplet-graph--text-lane-max)

Follow-up from `chaplet-ascii-compact` design §8.B: pathological fan-out
(>~10 concurrent lanes) widens the gutter. Add an OPTIONAL cap that hides
extra lanes without changing the default output.

## Changes

- **`chaplet-graph--text-lane-max`** — new `defcustom` (choice: `nil`
  "Unlimited" / `integer`, default `nil`), placed beside the other
  `chaplet-graph--text-*` defcustoms. `nil` = unlimited (default behavior
  unchanged).

- **`chaplet-graph--text-gutter`** — added a local `cap` binding and capped
  the gutter-glyph loop to `(min ncol cap)` when `cap` is a non-nil integer.
  Lanes at/after the cap render nothing; the node box is still emitted.
  Lane-threading state (`open-count`, `cols`) still tracks every lane and
  `p0`/`pk` still reference the full `cols` vector, so diamonds/merges keep
  their semantics — only the rendered gutter is truncated. If a dep lane
  falls at/after the cap its merge glyph (e.g. `┐`) is hidden (cosmetic).

- **`chaplet-graph--text-gutter` docstring** — updated to document the cap.

## Tests (chaplet-test.el)

- `chaplet-test--graph-fanout-beads` — fixture: 6 roots merging into one node
  → 6 concurrent lanes.
- `chaplet-test-graph-text-lane-max-default` — defcustom default `nil`; the
  existing fixture's box columns stay `(2 3 4 4)` (output unchanged).
- `chaplet-test-graph-text-lane-max-unlimited` — `nil` renders every lane;
  the merge bus spans all 6 lanes (`└────┐`).
- `chaplet-test-graph-text-lane-max` — cap 3: every rendered gutter ≤ 3
  columns, all 7 nodes appear once, `┐` (hidden lane) absent, box still
  follows the capped gutter (`└──  [m]`).

## Verification

`./check.sh` → exit 0, 120/120 (117 existing + 3 new) green, compile clean,
no warnings. Default output unchanged.
