#!/usr/bin/env bash
# chaplet install script — wire plugin into Emacs (Doom-aware).
# Usage:
#   ./install.sh            install
#   ./install.sh --uninstall  remove wiring (keeps repo)
# Re-run anytime (idempotent).

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SNIPPET_MARKER=";; === chaplet (managed by install.sh) ==="

# --- Detect Doom 3 (config in ~/.config/doom, emacs home ~/.config/emacs) ---
DOOM_CFG="${XDG_CONFIG_HOME:-$HOME/.config}/doom/config.el"
if [ -f "${DOOM_CFG}" ]; then
  TARGET="${DOOM_CFG}"
  echo "Doom detected: wiring into ${DOOM_CFG}"
else
  # Classic ~/.emacs.d
  TARGET="${HOME}/.emacs.d/init.el"
  mkdir -p "$(dirname "${TARGET}")"
  echo "Classic Emacs: wiring into ${TARGET}"
fi

uninstall() {
  if [ -f "${TARGET}" ]; then
    # Remove from first marker to end-of-chaplet line, inclusive
    awk -v start="${SNIPPET_MARKER}" -v end=";; === end chaplet ===" '
      $0 == start {skip=1}
      skip && $0 == end {skip=0; next}
      !skip' "${TARGET}" > "${TARGET}.tmp" && mv -f "${TARGET}.tmp" "${TARGET}"
    echo "Removed wiring from ${TARGET}"
  fi
  echo "Done."
  exit 0
}

[ "${1:-}" = "--uninstall" ] && uninstall

# --- Install: idempotent marker-based append ---
if [ -f "${TARGET}" ] && grep -qF "${SNIPPET_MARKER}" "${TARGET}"; then
  echo "Already wired; skipping."
else
  {
    echo ""
    echo "${SNIPPET_MARKER}"
    echo "(add-to-list 'load-path \"${PLUGIN_DIR}\")"
    echo "(require 'chaplet)"
    echo "(chaplet-mode 1)"
    echo ";; === end chaplet ==="
  } >> "${TARGET}"
  echo "Wired: ${TARGET}"
fi

echo "Installed."
echo "Restart Emacs (or M-x chaplet)."
