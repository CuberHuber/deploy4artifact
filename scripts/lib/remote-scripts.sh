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

# Refuses to go on when d4a-internal exists but is not an --internal network.
_d4a_gen_internal_net_guard() {
  cat <<'EOF'
if docker network inspect d4a-internal >/dev/null 2>&1; then
  if [ "$(docker network inspect -f '{{.Internal}}' d4a-internal)" != true ]; then
    echo "refusing to use network d4a-internal: it exists but is not internal (created without --internal); remove it or fix it by hand" >&2
    exit 1
  fi
fi
EOF
}

# Refuses to go on when the container named by the shell expression $1
# exists without the d4a.managed=true label.
_d4a_gen_owned_guard() {
  cat <<EOF
if docker inspect $1 >/dev/null 2>&1; then
  if [ "\$(docker inspect -f '{{index .Config.Labels "d4a.managed"}}' $1)" != true ]; then
    echo "refusing to replace $1: it was not created by deploy4artifact" >&2
    exit 1
  fi
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
  _d4a_gen_internal_net_guard
  _d4a_gen_owned_guard d4a-traefik
  cat <<'EOF'
root_ready() {
  mkdir -p "$D4A_ROOT/artifacts" "$D4A_ROOT/traefik" 2>/dev/null \
    && [ -w "$D4A_ROOT/artifacts" ] && [ -w "$D4A_ROOT/traefik" ] \
    && { [ ! -e "$D4A_ROOT/traefik/acme.json" ] || [ -w "$D4A_ROOT/traefik/acme.json" ]; }
}
if ! root_ready; then
  if ! sudo -n true >/dev/null 2>&1; then
    echo "cannot create or write $D4A_ROOT as $(id -un), and passwordless sudo is not available." >&2
    echo "Run this once on the VPS, then retry: sudo mkdir -p $D4A_ROOT && sudo chown $(id -un) $D4A_ROOT" >&2
    exit 1
  fi
  sudo -n mkdir -p "$D4A_ROOT/artifacts" "$D4A_ROOT/traefik"
  sudo -n chown -R "$(id -un)" "$D4A_ROOT"
fi
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

d4a_gen_run_script() {
  local slug="$1" domain="$2"
  d4a_validate_slug "$slug"
  d4a_validate_domain "$domain"
  d4a_validate_remote_root
  [[ "$D4A_HEALTH_WAIT" =~ ^[0-9]{1,3}$ ]] || d4a_die "invalid D4A_HEALTH_WAIT: $D4A_HEALTH_WAIT"
  _d4a_gen_header "SLUG=$slug" "DOMAIN=$domain" "D4A_ROOT=$D4A_REMOTE_ROOT" \
    "NGINX_IMAGE=$D4A_NGINX_IMAGE" "HEALTH_WAIT=$D4A_HEALTH_WAIT"
  _d4a_gen_docker_guard
  _d4a_gen_internal_net_guard
  cat <<'EOF'
name="d4a-$SLUG"
r="$name"
dir="$D4A_ROOT/artifacts/$SLUG"
[ -d "$dir" ] || { echo "artifact directory missing on the VPS: $dir" >&2; exit 1; }
EOF
  # shellcheck disable=SC2016 # expands in the generated script, not here
  _d4a_gen_owned_guard '"$name"'
  cat <<'EOF'
chmod -R a+rX "$dir"
docker rm -f "$name" >/dev/null 2>&1 || true
docker run -d --name "$name" --restart unless-stopped \
  --network d4a-internal \
  --security-opt no-new-privileges \
  -v "$dir:/usr/share/nginx/html:ro" \
  --health-cmd 'wget -q --spider http://127.0.0.1/ || exit 1' \
  --health-interval 5s --health-timeout 3s --health-retries 3 \
  --label d4a.managed=true \
  --label "d4a.slug=$SLUG" \
  --label traefik.enable=true \
  --label traefik.docker.network=d4a-internal \
  --label "traefik.http.routers.$r.rule=Host(\`$DOMAIN\`) && PathPrefix(\`/d4a/a/$SLUG/\`)" \
  --label "traefik.http.routers.$r.entrypoints=websecure" \
  --label "traefik.http.routers.$r.tls.certresolver=le" \
  --label "traefik.http.routers.$r.middlewares=$r-strip" \
  --label "traefik.http.routers.$r.service=$r" \
  --label "traefik.http.middlewares.$r-strip.stripprefix.prefixes=/d4a/a/$SLUG" \
  --label "traefik.http.routers.$r-slash.rule=Host(\`$DOMAIN\`) && Path(\`/d4a/a/$SLUG\`)" \
  --label "traefik.http.routers.$r-slash.entrypoints=websecure" \
  --label "traefik.http.routers.$r-slash.tls.certresolver=le" \
  --label "traefik.http.routers.$r-slash.middlewares=$r-addslash" \
  --label "traefik.http.routers.$r-slash.service=$r" \
  --label "traefik.http.middlewares.$r-addslash.redirectregex.regex=^(https://[^/]+/d4a/a/$SLUG)\$" \
  --label "traefik.http.middlewares.$r-addslash.redirectregex.replacement=\${1}/" \
  --label "traefik.http.middlewares.$r-addslash.redirectregex.permanent=true" \
  --label "traefik.http.services.$r.loadbalancer.server.port=80" \
  "$NGINX_IMAGE" >/dev/null
status=""
i=0
while [ "$i" -lt "$HEALTH_WAIT" ]; do
  status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$name")"
  if [ "$status" = healthy ]; then
    echo "container=healthy"
    exit 0
  fi
  i=$((i + 1))
  sleep 1
done
echo "container $name did not become healthy within ${HEALTH_WAIT}s (last status: ${status:-none})" >&2
docker logs --tail 20 "$name" >&2 || true
exit 1
EOF
}

d4a_gen_remove_script() {
  local slug="$1"
  d4a_validate_slug "$slug"
  d4a_validate_remote_root
  _d4a_gen_header "SLUG=$slug" "D4A_ROOT=$D4A_REMOTE_ROOT"
  _d4a_gen_docker_guard
  cat <<'EOF'
name="d4a-$SLUG"
if docker inspect "$name" >/dev/null 2>&1; then
  managed="$(docker inspect -f '{{index .Config.Labels "d4a.managed"}}' "$name")"
  if [ "$managed" != true ]; then
    echo "refusing to remove $name: it was not created by deploy4artifact" >&2
    exit 1
  fi
  docker rm -f "$name" >/dev/null
fi
rm -rf -- "$D4A_ROOT/artifacts/$SLUG"
echo "removed=$SLUG"
EOF
}

d4a_gen_list_script() {
  _d4a_gen_header
  _d4a_gen_docker_guard
  cat <<'EOF'
docker ps -a --filter label=d4a.managed=true --filter label=d4a.slug \
  --format '{{.Label "d4a.slug"}}\t{{.Status}}'
EOF
}

d4a_gen_health_script() {
  local slug="$1"
  d4a_validate_slug "$slug"
  _d4a_gen_header "SLUG=$slug"
  _d4a_gen_docker_guard
  cat <<'EOF'
name="d4a-$SLUG"
if docker inspect "$name" >/dev/null 2>&1; then
  docker inspect -f '{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$name"
else
  echo "missing"
fi
EOF
}
