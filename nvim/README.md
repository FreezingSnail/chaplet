# Chaplet Neovim plugin

Neovim support will live here as a sibling to the Emacs plugin. This
placeholder intentionally contains documentation only; no Lua is loadable yet.

## Planned tree

```text
nvim/
├── lua/chaplet/init.lua
├── lua/chaplet/bd.lua
├── lua/chaplet/config.lua
├── lua/chaplet/hl.lua
├── tests/bd_spec.lua
├── tests/hl_spec.lua
├── check.sh
└── install.sh
```

The Lua implementation and its test harness arrive with epic `chaplet-8mj`.
Until then, do not add Lua files, `check.sh`, `install.sh`, or a green stub in
this directory. A harness that reports success without tests would hide the
missing implementation and would have to be reverted later.

## Inherited repository rules

- Resolve the `bd` test double from the repository root at `../test/fake-bd`.
  Keep one shared double so both plugins exercise the same CLI contract.
- Measure the Neovim plugin against the repository-level [`PARITY.md`](../PARITY.md)
  contract.
- When the local harness arrives, `nvim/check.sh` must use the same exit codes
  as the root dispatcher: `0` green, `1` compile error, `2` test failure,
  `3` probe failure, and `5` warnings. The root dispatcher propagates those
  codes unchanged.

`nvim/check.sh` and `nvim/install.sh` are therefore deliberately absent. Until
epic `chaplet-8mj` supplies them, the root `check.sh` and `install.sh` skip this
plugin tree.
