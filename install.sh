#!/usr/bin/env bash
# chaplet installer dispatcher.
# Usage: ./install.sh [--emacs] [--nvim] [--uninstall] [delegate args...]

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  printf '%s\n' \
    'Usage: ./install.sh [--emacs] [--nvim] [--uninstall] [delegate args...]' \
    '       ./install.sh --help'
}

select_emacs=0
select_nvim=0
explicit_selection=0
uninstall=0
forwarded=()

for arg in "$@"; do
  case "$arg" in
    --emacs)
      select_emacs=1
      explicit_selection=1
      ;;
    --nvim)
      select_nvim=1
      explicit_selection=1
      ;;
    --uninstall)
      uninstall=1
      forwarded+=("$arg")
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      usage >&2
      printf 'Unknown option: %s\n' "$arg" >&2
      exit 64
      ;;
    *)
      forwarded+=("$arg")
      ;;
  esac
done

plugins=()
if [[ "$explicit_selection" -eq 0 || "$select_emacs" -eq 1 ]]; then
  plugins+=(emacs)
fi
if [[ "$explicit_selection" -eq 0 || "$select_nvim" -eq 1 ]]; then
  plugins+=(nvim)
fi

for plugin in "${plugins[@]}"; do
  installer="${SCRIPT_DIR}/${plugin}/install.sh"
  if [[ ! -x "$installer" ]]; then
    printf 'SKIP %s: no install.sh\n' "$plugin"
    continue
  fi

  if "$installer" "${forwarded[@]}"; then
    if [[ "$uninstall" -eq 1 ]]; then
      printf 'UNINSTALLED %s\n' "$plugin"
    else
      printf 'INSTALLED %s\n' "$plugin"
    fi
  else
    status=$?
    exit "$status"
  fi
done
