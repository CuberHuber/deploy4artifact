#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2026 CuberHuber
# SPDX-License-Identifier: MIT
#
# Deploy a fetched artifact directory to a VPS over SSH. All connection
# details are read from the OS keychain by profile name; nothing is read
# from disk, argv, or the environment except the profile name itself.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib/common.sh
source "$DIR/lib/common.sh"
# shellcheck source=./lib/validate.sh
source "$DIR/lib/validate.sh"
# shellcheck source=./lib/keychain.sh
source "$DIR/lib/keychain.sh"
# shellcheck source=./lib/remote.sh
source "$DIR/lib/remote.sh"

usage() {
  cat <<'EOF'
Usage: deploy-vps.sh <profile> <source-dir> <remote-path>

Deploys <source-dir> to <remote-path> on the VPS identified by <profile>.
Host, user, port, and auth details come from the OS keychain — see the
vps-profiles skill to create a profile first.
EOF
}

trap d4a_remote_cleanup EXIT

main() {
  [[ $# -eq 3 ]] || { usage; exit 2; }
  local profile="$1" src="$2" remote_path="$3"
  d4a_validate_profile_name "$profile"
  [[ -d "$src" ]] || d4a_die "source directory not found: $src"
  d4a_validate_remote_path "$remote_path"
  d4a_remote_open "$profile"
  d4a_log "deploying to ${D4A_REMOTE_TARGET}:${remote_path} (profile: $profile)"
  d4a_remote_rsync "$src" "$remote_path"
  d4a_log "deploy complete"
}

main "$@"
