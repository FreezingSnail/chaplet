#!/usr/bin/env bash
# Root plugin harness dispatcher.

set -uo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  printf '%s\n' \
    'Usage: ./check.sh [flags...]' \
    '       ./check.sh emacs [args...]' \
    '       ./check.sh nvim [args...]'
}

run_plugin() {
  local plugin="$1"
  shift
  local harness="$root_dir/$plugin/check.sh"

  if [[ ! -x "$harness" ]]; then
    printf 'SKIP %s: no check.sh\n' "$plugin"
    return 0
  fi

  "$harness" "$@"
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
  probe)
    printf '%s\n' 'check.sh: probe requires an emacs or nvim selector' >&2
    usage >&2
    exit 64
    ;;
  emacs|nvim)
    plugin="$1"
    shift
    run_plugin "$plugin" "$@"
    exit $?
    ;;
esac

if [[ -z "${CHAPLET_HARNESS_TEST+x}" ]]; then
  "$root_dir/test/harness-test.sh"
  status=$?
  if [[ "$status" -ne 0 ]]; then
    exit 2
  fi
fi

for plugin in emacs nvim; do
  run_plugin "$plugin" "$@"
  status=$?
  if [[ "$status" -ne 0 ]]; then
    exit "$status"
  fi
done
