#!/usr/bin/env bats
# SPDX-FileCopyrightText: Copyright (c) 2026 CuberHuber
# SPDX-License-Identifier: MIT
#
# Runs the real generated proxy and run scripts against the local Docker
# daemon and checks the Traefik routes end to end. The proxy binds host
# ports 80 and 443, so the file skips when either is taken or when a
# d4a-traefik container already exists. Teardown removes only what this run
# created.

_port_in_use() {
  # curl exits 7 when nothing listens on the port.
  local rc=0
  curl -s --noproxy '*' -o /dev/null --max-time 2 "http://127.0.0.1:$1/" || rc=$?
  [ "$rc" -ne 7 ]
}

_net_marker() {
  if ! docker network inspect "$1" >/dev/null 2>&1; then
    touch "$D4A_IT_ROOT/.created-$1"
  fi
}

setup_file() {
  command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1 || skip "Docker is not available"
  command -v curl >/dev/null 2>&1 || skip "curl is not available"
  if docker inspect d4a-traefik >/dev/null 2>&1; then
    skip "a d4a-traefik container already exists; not touching it"
  fi
  if _port_in_use 80 || _port_in_use 443; then
    skip "host port 80 or 443 is already in use; the proxy test needs both"
  fi
  SCRIPTS="$(cd "$BATS_TEST_DIRNAME/../../scripts" && pwd)"
  D4A_IT_ROOT="$(mktemp -d)"
  D4A_IT_SLUG="itproxy-$$"
  export SCRIPTS D4A_IT_ROOT D4A_IT_SLUG
  _net_marker d4a-internal
  _net_marker d4a-public
  local libs src
  libs="source '$SCRIPTS/lib/common.sh'; source '$SCRIPTS/lib/validate.sh'; source '$SCRIPTS/lib/remote-scripts.sh'"
  touch "$D4A_IT_ROOT/.created-d4a-traefik"
  env D4A_REMOTE_ROOT="$D4A_IT_ROOT/srv" bash -c "$libs; script=\"\$(d4a_gen_proxy_script ops@example.com)\"; bash -c \"\$script\"" \
    > "$D4A_IT_ROOT/proxy.out" 2>&1 || { cat "$D4A_IT_ROOT/proxy.out" >&2; return 1; }
  # A single top-level page that is not index.html also covers the entry copy.
  src="$D4A_IT_ROOT/fetched"
  mkdir -p "$src"
  printf '<html><head></head><body>hello-through-traefik</body></html>\n' > "$src/page.html"
  bash "$SCRIPTS/prepare-artifact.sh" "$src" "$D4A_IT_SLUG" "$D4A_IT_ROOT/srv/artifacts/$D4A_IT_SLUG" >/dev/null
  env D4A_REMOTE_ROOT="$D4A_IT_ROOT/srv" D4A_HEALTH_WAIT=60 \
    bash -c "$libs; script=\"\$(d4a_gen_run_script $D4A_IT_SLUG d4a.example.com)\"; bash -c \"\$script\"" \
    > "$D4A_IT_ROOT/run.out" 2>&1 || { cat "$D4A_IT_ROOT/run.out" >&2; return 1; }
}

teardown_file() {
  [ -n "${D4A_IT_ROOT:-}" ] || return 0
  docker rm -f "d4a-$D4A_IT_SLUG" >/dev/null 2>&1 || true
  if [ -e "$D4A_IT_ROOT/.created-d4a-traefik" ]; then
    docker rm -f d4a-traefik >/dev/null 2>&1 || true
  fi
  local net
  for net in d4a-internal d4a-public; do
    if [ -e "$D4A_IT_ROOT/.created-$net" ]; then
      docker network rm "$net" >/dev/null 2>&1 || true
    fi
  done
  rm -rf "$D4A_IT_ROOT"
}

# Prints "<code> <redirect-url>" for an HTTPS request routed to the local proxy,
# retrying for up to 30s while Traefik picks up the container labels.
_fetch() {
  local path="$1" want="$2" out="" i=0
  while [ "$i" -lt 30 ]; do
    # --noproxy: an HTTPS_PROXY in the environment would bypass --resolve.
    out="$(curl -sk --noproxy '*' --max-time 5 --resolve d4a.example.com:443:127.0.0.1 \
      -o "$D4A_IT_ROOT/body" -w '%{http_code} %{redirect_url}' \
      "https://d4a.example.com$path" || true)"
    case "$out" in "$want"*) break ;; *) ;; esac
    i=$((i + 1))
    sleep 1
  done
  printf '%s' "$out"
}

@test "the proxy script starts Traefik and the run script gets healthy" {
  run cat "$D4A_IT_ROOT/proxy.out"
  [[ "$output" == *"traefik=started"* ]] || false
  run cat "$D4A_IT_ROOT/run.out"
  [[ "$output" == *"container=healthy"* ]] || false
}

@test "Traefik serves the artifact page under /d4a/a/<slug>/" {
  run _fetch "/d4a/a/$D4A_IT_SLUG/" 200
  [[ "$output" == "200 "* ]] || false
  grep -q 'hello-through-traefik' "$D4A_IT_ROOT/body"
  grep -qF "<base href=\"/d4a/a/$D4A_IT_SLUG/\">" "$D4A_IT_ROOT/body"
}

@test "Traefik serves the download zip under /d4a/a/<slug>/.d4a/download.zip" {
  run _fetch "/d4a/a/$D4A_IT_SLUG/.d4a/download.zip" 200
  [[ "$output" == "200 "* ]] || false
  unzip -l "$D4A_IT_ROOT/body" | grep -q ' page.html$'
}

@test "Traefik redirects /d4a/a/<slug> to the trailing-slash URL" {
  run _fetch "/d4a/a/$D4A_IT_SLUG" 30
  [[ "$output" == 301" "* || "$output" == 308" "* ]] || false
  [[ "$output" == *"/d4a/a/$D4A_IT_SLUG/" ]] || false
}
