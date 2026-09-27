#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2026 CuberHuber
# SPDX-License-Identifier: MIT
#
# Deploy a prepared artifact (see prepare-artifact.sh) to a VPS profile:
# sync its files, run it in an nginx container on the no-egress
# d4a-internal network behind Traefik, and record it in the local registry.
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
# shellcheck source=./lib/remote-scripts.sh
source "$DIR/lib/remote-scripts.sh"
# shellcheck source=./lib/registry.sh
source "$DIR/lib/registry.sh"

trap d4a_remote_cleanup EXIT

usage() {
  cat <<'EOF'
Usage: deploy.sh <profile> <prepared-dir> <slug>

Needs Docker and the d4a-traefik proxy on the VPS (see bootstrap-vps.sh).
Prints "url=..." and "download=..." on success.
EOF
}

main() {
  [[ $# -eq 3 ]] || { usage; exit 2; }
  local profile="$1" staging="$2" slug="$3" domain check_script run_script check state now
  d4a_validate_profile_name "$profile"
  d4a_validate_slug "$slug"
  [[ -f "$staging/.d4a/download.zip" ]] \
    || d4a_die "$staging is not a prepared artifact — run prepare-artifact.sh first"
  domain="$(d4a_kc_get "$profile" site_domain)" \
    || d4a_die "no site_domain for profile '$profile' — set it with: vps-profile.sh set-site $profile <domain> <email>"
  d4a_validate_domain "$domain"
  check_script="$(d4a_gen_check_script)"
  run_script="$(d4a_gen_run_script "$slug" "$domain")"

  d4a_remote_open "$profile"
  check="$(d4a_remote_run "$check_script")"
  state="$(d4a_kv docker "$check")"
  [[ "$state" == ok ]] \
    || d4a_die "Docker is not usable on the VPS (docker=$state) — run: bootstrap-vps.sh $profile check"
  [[ "$(d4a_kv traefik "$check")" == running ]] \
    || d4a_die "the d4a-traefik proxy is not running — run: bootstrap-vps.sh $profile ensure-proxy"

  d4a_log "syncing '$slug' to ${D4A_REMOTE_TARGET}"
  d4a_remote_rsync "$staging" "$D4A_REMOTE_ROOT/artifacts/$slug"
  d4a_remote_run "$run_script" >&2
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  d4a_reg_put "$slug" "$profile" "$now"
  printf 'url=https://%s/d4a/a/%s/\n' "$domain" "$slug"
  printf 'download=https://%s/d4a/a/%s/.d4a/download.zip\n' "$domain" "$slug"
}

main "$@"
