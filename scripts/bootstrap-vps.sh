#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2026 CuberHuber
# SPDX-License-Identifier: MIT
#
# Inspect or prepare a VPS for deploy4artifact: report Docker and proxy
# state, install Docker from the distro package manager, or start the
# Traefik proxy and the d4a networks. Each action is idempotent.
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

trap d4a_remote_cleanup EXIT

usage() {
  cat <<'EOF'
Usage: bootstrap-vps.sh <profile> check|install-docker|ensure-proxy

check           print docker=ok|no-access|missing, sudo=ok|no, traefik=running|missing
install-docker  install Docker with apt-get or dnf (needs root or passwordless sudo)
ensure-proxy    create /srv/deploy4artifact, the d4a networks, and the Traefik proxy
EOF
}

main() {
  [[ $# -eq 2 ]] || { usage; exit 2; }
  local profile="$1" action="$2" email script
  d4a_validate_profile_name "$profile"
  case "$action" in
    check) script="$(d4a_gen_check_script)" ;;
    install-docker) script="$(d4a_gen_install_docker_script)" ;;
    ensure-proxy)
      email="$(d4a_kc_get "$profile" acme_email)" \
        || d4a_die "no acme_email for profile '$profile' — set it with: vps-profile.sh set-site $profile <domain> <email>"
      script="$(d4a_gen_proxy_script "$email")"
      ;;
    *) usage; exit 2 ;;
  esac
  d4a_remote_open "$profile"
  d4a_remote_run "$script"
}

main "$@"
