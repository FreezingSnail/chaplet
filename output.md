# chaplet-css.2 — tests: major-mode, read-only, cursor, no image-mode

## Change

`chaplet-test.el` — added two ERT tests (tag `:chaplet`):

- `chaplet-test-graph-major-mode` — after `(chaplet-graph)` with fake-bd,
  asserts `(derived-mode-p 'chaplet-graph-mode)`, `(eq major-mode
  'chaplet-graph-mode)`, `buffer-read-only` t, and `cursor-type` nil.
- `chaplet-test-graph-no-image-mode` — stubs `image-mode` to signal an
  error, then runs `chaplet-graph--render` through both the text path
  (images unavailable) and the image path (`svg-image` stubbed to a valid
  image); asserts `image-mode` is never invoked and both paths succeed.

Existing tests unchanged and still passing: `chaplet-test-graph-mode-map`,
`-mouse-bindings`, `-headless-render`, `chaplet-test-bar-graph-installed`,
`-keys-match-keymap`.

## Interface contract verified

After `(chaplet-graph)` the buffer has:
- major-mode `chaplet-graph-mode` (derived from `special-mode`),
- `buffer-read-only` t,
- `cursor-type` nil,
- keys n/p/RET/d/f/g/c/q bound in `chaplet-graph-mode-map`,
- node mouse bindings installed by `chaplet-graph--render`,
- keybinding bar still installed,
- no `image-mode` usage.

## Verification

`./check.sh` — 107/107 tests pass, compile clean, no warnings (exit 0).
