#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2026 CuberHuber
# SPDX-License-Identifier: MIT
#
# Scan a fetched artifact for Claude runtime capability calls (window.claude),
# which have no backend once self-hosted and silently do nothing.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib/common.sh
source "$DIR/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: check-capabilities.sh <artifact-dir>

Exits 0 with no output if no HTML/JS file uses window.claude. Exits 3 and
prints each file that does (relative to <artifact-dir>) otherwise.
EOF
}

main() {
  [[ $# -eq 1 ]] || { usage; exit 2; }
  local src="$1" hits
  [[ -d "$src" ]] || d4a_die "artifact directory not found: $src"
  hits="$(cd "$src" && grep -rlE \
    -e 'window\.claude([^A-Za-z0-9_$]|$)' \
    -e 'window\[.claude.\]' \
    --include='*.html' --include='*.htm' --include='*.js' --include='*.mjs' \
    . || true)"
  if [[ -n "$hits" ]]; then
    printf '%s\n' "$hits" | sed 's|^\./||' | sort
    exit 3
  fi
}

main "$@"
