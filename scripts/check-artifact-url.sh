#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2026 CuberHuber
# SPDX-License-Identifier: MIT
#
# Validate that a URL is a claude.ai artifact link before anything fetches
# it. Exits non-zero with an explanation on any other host or shape.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib/common.sh
source "$DIR/lib/common.sh"
# shellcheck source=./lib/validate.sh
source "$DIR/lib/validate.sh"

usage() {
  cat <<'EOF'
Usage: check-artifact-url.sh <url>

Exits 0 and prints nothing if <url> is a claude.ai artifact URL. Exits
non-zero with an explanation otherwise.
EOF
}

main() {
  [[ $# -eq 1 ]] || { usage; exit 2; }
  d4a_validate_artifact_url "$1"
}

main "$@"
