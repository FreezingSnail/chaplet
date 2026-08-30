#!/usr/bin/env bash
# check.sh — Lua load/lint and Plenary specs.
#
# Usage: ./check.sh | ./check.sh -c
# Exit codes: 0 green; 1 load/lint failure; 2 spec failure; 5 warnings.

set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

resolve_plenary() {
  local candidate
  if [[ -n "${CHAPLET_PLENARY:-}" && -d "$CHAPLET_PLENARY" ]]; then
    printf '%s\n' "$CHAPLET_PLENARY"
    return 0
  fi

  candidate="$HOME/.local/share/nvim/lazy/plenary.nvim"
  if [[ -d "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  for candidate in "$HOME"/.local/share/nvim/site/pack/*/start/plenary.nvim; do
    if [[ -d "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  printf '%s\n' 'check.sh: Plenary not found; set CHAPLET_PLENARY to its directory.' >&2
  return 1
}

plenary="$(resolve_plenary)" || exit 1
export CHAPLET_PLENARY="$plenary"

load_modules() {
  echo '=== LOAD ==='
  nvim --headless -u tests/minimal_init.lua \
    -c "lua local ok, err = pcall(function() for _, file in ipairs(vim.fn.globpath('lua/chaplet', '**/*.lua', false, true)) do local module = file:gsub('^lua/', ''):gsub('%.lua$', ''):gsub('/', '.'); require(module) end end); if not ok then vim.api.nvim_err_writeln(err); vim.cmd('cquit 1') end" \
    -c 'qa' || exit 1
}

lint() {
  echo '=== LINT ==='
  local output status
  output="$(luacheck --codes lua 2>&1)"
  status=$?
  printf '%s\n' "$output"
  if [[ "$status" -eq 0 ]]; then
    return 0
  fi
  if [[ "$status" -eq 1 ]] && [[ "$output" == *"(W"* ]]; then
    exit 5
  fi
  exit 1
}

specs() {
  echo '=== SPECS ==='
  nvim --headless -u tests/minimal_init.lua \
    -c "PlenaryBustedDirectory tests { minimal_init = 'tests/minimal_init.lua' }" \
    || exit 2
}

if command -v luacheck >/dev/null 2>&1; then
  lint
else
  load_modules
fi

if [[ "${1:-}" == '-c' ]]; then
  exit 0
fi

specs
