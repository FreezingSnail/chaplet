#!/usr/bin/env bash
# Permanent subprocess assertions for the root harness dispatcher.

set -uo pipefail

script_path="${BASH_SOURCE[0]}"
script_dir="$(cd "$(dirname "$script_path")" && pwd)"
root_dir="$(cd "$script_dir/.." && pwd)"

stub_plugin="${script_path%/check.sh}"
stub_plugin="${stub_plugin##*/}"
if [[ "$stub_plugin" == emacs || "$stub_plugin" == nvim ]]; then
  printf 'STUB %s ARGV:' "$stub_plugin"
  for argument in "$@"; do
    printf ' <%s>' "$argument"
  done
  printf '\n'
  if [[ "$stub_plugin" == emacs ]]; then
    exit "${EMACS_EXIT:-0}"
  fi
  exit "${NVIM_EXIT:-0}"
fi

worktree=""
cleanup() {
  if [[ -n "$worktree" ]]; then
    rm -rf "$worktree"
  fi
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_status() {
  local expected="$1"
  local actual="$2"
  local context="$3"
  [[ "$actual" == "$expected" ]] || fail "$context: expected $expected, got $actual"
}

assert_contains() {
  local output="$1"
  local expected="$2"
  local context="$3"
  [[ "$output" == *"$expected"* ]] || fail "$context: missing $expected"
}

assert_not_contains() {
  local output="$1"
  local unexpected="$2"
  local context="$3"
  [[ "$output" != *"$unexpected"* ]] || fail "$context: unexpectedly found $unexpected"
}

run_dispatch() {
  output="$("$worktree/check.sh" "$@" 2>&1)"
  status=$?
}

assert_plugin_code() {
  local plugin="$1"
  local code="$2"

  if [[ "$plugin" == emacs ]]; then
    output="$(EMACS_EXIT="$code" "$worktree/check.sh" emacs 2>&1)"
  else
    output="$(NVIM_EXIT="$code" "$worktree/check.sh" nvim 2>&1)"
  fi
  status=$?
  assert_status "$code" "$status" "$plugin exit propagation"
}

export CHAPLET_HARNESS_TEST=1
worktree="$(mktemp -d "$script_dir/.harness-test.XXXXXX")" || fail 'mktemp failed'

cp -f "$root_dir/check.sh" "$worktree/check.sh" || fail 'copy dispatcher failed'
mkdir -p "$worktree/emacs" "$worktree/nvim" || fail 'create plugin directories failed'
cp -f "$script_path" "$worktree/emacs/check.sh" || fail 'copy emacs stub failed'
cp -f "$script_path" "$worktree/nvim/check.sh" || fail 'copy nvim stub failed'
chmod +x "$worktree/check.sh" "$worktree/emacs/check.sh" "$worktree/nvim/check.sh" \
  || fail 'make stubs executable failed'

for code in 0 1 2 3 5; do
  assert_plugin_code emacs "$code"
  assert_plugin_code nvim "$code"
done

output="$(EMACS_EXIT=3 NVIM_EXIT=5 "$worktree/check.sh" --forwarded 2>&1)"
status=$?
assert_status 3 "$status" 'first failing plugin'
assert_contains "$output" 'STUB emacs ARGV: <--forwarded>' 'first failing plugin'
assert_not_contains "$output" 'STUB nvim ARGV:' 'first failing plugin'

output="$(EMACS_EXIT=0 "$worktree/check.sh" emacs -c 2>&1)"
status=$?
assert_status 0 "$status" 'selected emacs argv'
assert_contains "$output" 'STUB emacs ARGV: <-c>' 'selected emacs argv'

output="$(EMACS_EXIT=0 NVIM_EXIT=0 "$worktree/check.sh" --unknown value 2>&1)"
status=$?
assert_status 0 "$status" 'unknown flags'
assert_contains "$output" 'STUB emacs ARGV: <--unknown> <value>' 'unknown flags emacs'
assert_contains "$output" 'STUB nvim ARGV: <--unknown> <value>' 'unknown flags nvim'

run_dispatch probe
assert_status 64 "$status" 'unselected probe'
assert_contains "$output" 'probe requires an emacs or nvim selector' 'unselected probe'

chmod -x "$worktree/nvim/check.sh" || fail 'make nvim stub non-executable failed'
run_dispatch nvim
assert_status 0 "$status" 'non-executable selected nvim'
assert_contains "$output" 'SKIP nvim: no check.sh' 'non-executable selected nvim'

rm -f "$worktree/nvim/check.sh"
run_dispatch
assert_status 0 "$status" 'missing nvim harness'
assert_contains "$output" 'SKIP nvim: no check.sh' 'missing nvim harness'

rmdir "$worktree/nvim" || fail 'remove empty nvim directory failed'
run_dispatch
assert_status 0 "$status" 'absent nvim tree'
assert_contains "$output" 'SKIP nvim: no check.sh' 'absent nvim tree'

run_dispatch --help
assert_status 0 "$status" 'help'
assert_contains "$output" 'Usage: ./check.sh' 'help'

printf 'harness assertions: PASS\n'
