#!/usr/bin/env bash
# harness/check.sh — orchestrator gate entry point.
#
# The Maduin land step runs "<worktree>/harness/check.sh" at a hardcoded path
# (maduin-pipeline--run-gate) and refuses to land on a non-zero exit. Chaplet's
# own harness lives elsewhere, and it MOVES during the monorepo restructure
# (root ./check.sh -> emacs/check.sh plus a root dispatcher), so this shim
# resolves the real harness at run time instead of pinning either layout.
#
# Resolution order, first executable wins:
#   ./check.sh        root dispatcher (post-restructure) or legacy root harness
#   ./emacs/check.sh  plugin-local harness while no root dispatcher exists
#
# Arguments are forwarded verbatim in argv form, and the delegate's exit code is
# propagated unchanged, so the documented contract still holds end to end:
#   0 green · 1 compile error · 2 test fail · 3 probe fail · 5 warnings
# 127 is reserved for "no harness found", matching the missing-script code the
# gate itself uses.

set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 127

if [[ -x ./check.sh ]]; then
  exec ./check.sh "$@"
elif [[ -x ./emacs/check.sh ]]; then
  exec ./emacs/check.sh "$@"
fi

echo "chaplet: no plugin harness found (looked for ./check.sh, ./emacs/check.sh)" >&2
exit 127
