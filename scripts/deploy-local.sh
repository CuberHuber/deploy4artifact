#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2026 CuberHuber
# SPDX-License-Identifier: MIT
#
# Deploy a fetched artifact directory to a local destination.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib/common.sh
source "$DIR/lib/common.sh"
# shellcheck source=./lib/validate.sh
source "$DIR/lib/validate.sh"

usage() {
  cat <<'EOF'
Usage: deploy-local.sh <source-dir> <destination-dir>

Copies the contents of <source-dir> (a fetched artifact) into
<destination-dir>. Refuses relative paths, '..' traversal, and known
system directories.
EOF
}

main() {
  [[ $# -eq 2 ]] || { usage; exit 2; }
  local src="$1" dest="$2" count
  [[ -d "$src" ]] || d4a_die "source directory not found: $src"
  d4a_validate_local_dest "$dest"
  d4a_require_cmd rsync

  mkdir -p "$dest"
  rsync -a --delete-after -- "$src"/ "$dest"/
  count="$(find "$src" -type f | wc -l | tr -d ' ')"
  d4a_log "deployed $count file(s) to $dest"
}

main "$@"
