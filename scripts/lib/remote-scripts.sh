#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2026 CuberHuber
# SPDX-License-Identifier: MIT
#
# Pure generators for the bash scripts deploy4artifact runs on a VPS. Each
# function validates its inputs and prints a complete script; nothing here
# touches the network or the filesystem. Values are embedded only after
# validation, as single-quoted assignments. Not meant to be executed
# directly; source common.sh and validate.sh first.
set -euo pipefail

: "${D4A_REMOTE_ROOT:=/srv/deploy4artifact}"
: "${D4A_HEALTH_WAIT:=30}"
D4A_TRAEFIK_IMAGE="traefik:v3"
# shellcheck disable=SC2034 # consumed by Task 7's run-script generator appended to this file
D4A_NGINX_IMAGE="nginx:stable-alpine"

d4a_validate_remote_root() {
  [[ "$D4A_REMOTE_ROOT" =~ ^/[A-Za-z0-9/_.-]+$ && "$D4A_REMOTE_ROOT" != *..* ]] \
    || d4a_die "invalid D4A_REMOTE_ROOT: $D4A_REMOTE_ROOT"
}

_d4a_gen_header() {
  local kv
  printf '#!/usr/bin/env bash\nset -euo pipefail\n'
  for kv in "$@"; do
    printf "%s='%s'\n" "${kv%%=*}" "${kv#*=}"
  done
}

_d4a_gen_docker_guard() {
  cat <<'EOF'
if ! docker info >/dev/null 2>&1; then
  echo "cannot reach Docker as $(id -un): deploy as root or add this user to the docker group" >&2
  exit 1
fi
EOF
}

d4a_gen_check_script() {
  _d4a_gen_header
  cat <<'EOF'
docker_state=missing
if command -v docker >/dev/null 2>&1; then
  if docker info >/dev/null 2>&1; then docker_state=ok; else docker_state=no-access; fi
fi
echo "docker=$docker_state"
if [ "$(id -u)" -eq 0 ] || sudo -n true >/dev/null 2>&1; then echo "sudo=ok"; else echo "sudo=no"; fi
if [ "$docker_state" = ok ] \
  && [ -n "$(docker ps -q --filter 'name=^d4a-traefik$' --filter status=running)" ]; then
  echo "traefik=running"
else
  echo "traefik=missing"
fi
EOF
}

d4a_gen_install_docker_script() {
  _d4a_gen_header
  cat <<'EOF'
SUDO=""
if [ "$(id -u)" -ne 0 ]; then SUDO="sudo -n"; fi
if command -v apt-get >/dev/null 2>&1; then
  $SUDO apt-get update -y
  $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io
elif command -v dnf >/dev/null 2>&1; then
  $SUDO dnf install -y docker
else
  echo "no apt-get or dnf found: install Docker by hand (https://docs.docker.com/engine/install/)" >&2
  exit 1
fi
$SUDO systemctl enable --now docker
echo "docker=installed"
if [ "$(id -u)" -ne 0 ]; then
  echo "note: $(id -un) still needs Docker access: add it to the docker group (root-equivalent) or deploy as root" >&2
fi
EOF
}

d4a_gen_proxy_script() {
  local email="$1"
  d4a_validate_email "$email"
  d4a_validate_remote_root
  _d4a_gen_header "D4A_ROOT=$D4A_REMOTE_ROOT" "ACME_EMAIL=$email" "TRAEFIK_IMAGE=$D4A_TRAEFIK_IMAGE"
  _d4a_gen_docker_guard
  cat <<'EOF'
SUDO=""
if [ "$(id -u)" -ne 0 ]; then SUDO="sudo -n"; fi
$SUDO mkdir -p "$D4A_ROOT/artifacts" "$D4A_ROOT/traefik"
$SUDO chown -R "$(id -un)" "$D4A_ROOT"
touch "$D4A_ROOT/traefik/acme.json"
chmod 600 "$D4A_ROOT/traefik/acme.json"
docker network inspect d4a-internal >/dev/null 2>&1 || docker network create --internal d4a-internal >/dev/null
docker network inspect d4a-public >/dev/null 2>&1 || docker network create d4a-public >/dev/null
if [ -n "$(docker ps -q --filter 'name=^d4a-traefik$' --filter status=running)" ]; then
  echo "traefik=already-running"
  exit 0
fi
docker rm -f d4a-traefik >/dev/null 2>&1 || true
docker run -d --name d4a-traefik --restart unless-stopped \
  --network d4a-public -p 80:80 -p 443:443 \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  -v "$D4A_ROOT/traefik/acme.json:/acme.json" \
  --label d4a.managed=true --label d4a.role=proxy \
  "$TRAEFIK_IMAGE" \
  --providers.docker=true \
  --providers.docker.exposedbydefault=false \
  --providers.docker.network=d4a-internal \
  --entrypoints.web.address=:80 \
  --entrypoints.websecure.address=:443 \
  --entrypoints.web.http.redirections.entrypoint.to=websecure \
  --entrypoints.web.http.redirections.entrypoint.scheme=https \
  "--certificatesresolvers.le.acme.email=$ACME_EMAIL" \
  --certificatesresolvers.le.acme.storage=/acme.json \
  --certificatesresolvers.le.acme.httpchallenge.entrypoint=web >/dev/null
docker network connect d4a-internal d4a-traefik
echo "traefik=started"
EOF
}
