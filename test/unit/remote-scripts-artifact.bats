#!/usr/bin/env bats
# SPDX-FileCopyrightText: Copyright (c) 2026 CuberHuber
# SPDX-License-Identifier: MIT

load '../helpers/stubs'

setup() {
  d4a_stubs_setup
  ROOT="$(mktemp -d)"
  export D4A_REMOTE_ROOT="$ROOT"
  mkdir -p "$ROOT/artifacts/demo"
  printf 'hi' > "$ROOT/artifacts/demo/index.html"
  # shellcheck source=/dev/null
  source "$SCRIPTS/lib/common.sh"
  # shellcheck source=/dev/null
  source "$SCRIPTS/lib/validate.sh"
  # shellcheck source=/dev/null
  source "$SCRIPTS/lib/remote-scripts.sh"
}

teardown() {
  rm -rf "$ROOT"
  d4a_stubs_teardown
}

@test "every artifact script is valid bash" {
  d4a_gen_run_script demo d4a.example.com | bash -n
  d4a_gen_remove_script demo | bash -n
  d4a_gen_list_script | bash -n
  d4a_gen_health_script demo | bash -n
}

@test "run script replaces the old container before starting the new one" {
  run bash -c "$(d4a_gen_run_script demo d4a.example.com)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"container=healthy"* ]]
  rm_line="$(grep -n '^rm -f d4a-demo' "$STUB_LOG/docker.args" | cut -d: -f1)"
  run_line="$(grep -n '^run -d --name d4a-demo' "$STUB_LOG/docker.args" | cut -d: -f1)"
  [ -n "$rm_line" ] && [ -n "$run_line" ] && [ "$rm_line" -lt "$run_line" ]
}

@test "run script routes the path prefix, joins only d4a-internal, and publishes no ports" {
  bash -c "$(d4a_gen_run_script demo d4a.example.com)"
  run_args="$(grep '^run -d --name d4a-demo' "$STUB_LOG/docker.args")"
  [[ "$run_args" == *'--network d4a-internal'* ]]
  [[ "$run_args" == *'traefik.http.routers.d4a-demo.rule=Host(`d4a.example.com`) && PathPrefix(`/d4a/a/demo/`)'* ]]
  [[ "$run_args" == *'traefik.http.middlewares.d4a-demo-strip.stripprefix.prefixes=/d4a/a/demo'* ]]
  [[ "$run_args" == *'traefik.http.routers.d4a-demo.tls.certresolver=le'* ]]
  [[ "$run_args" == *'d4a.managed=true'* ]]
  [[ "$run_args" == *":/usr/share/nginx/html:ro"* ]]
  [[ "$run_args" != *' -p '* ]]
}

@test "run script makes files synced with a strict umask readable by nginx" {
  chmod 600 "$ROOT/artifacts/demo/index.html"
  bash -c "$(d4a_gen_run_script demo d4a.example.com)"
  [ "$(ls -l "$ROOT/artifacts/demo/index.html" | cut -c8)" = "r" ]
}

@test "run script fails and reports when the container never gets healthy" {
  export STUB_DOCKER_INSPECT=starting D4A_HEALTH_WAIT=2
  run bash -c "$(d4a_gen_run_script demo d4a.example.com)"
  [ "$status" -ne 0 ]
  [[ "$output" == *"did not become healthy"* ]]
}

@test "run script fails when the artifact files are missing on the VPS" {
  rm -rf "$ROOT/artifacts/demo"
  run bash -c "$(d4a_gen_run_script demo d4a.example.com)"
  [ "$status" -ne 0 ]
  [[ "$output" == *"artifact directory missing"* ]]
}

@test "generators refuse an invalid slug or domain" {
  run d4a_gen_run_script "../x" d4a.example.com
  [ "$status" -ne 0 ]
  run d4a_gen_run_script demo "evil.com\`"
  [ "$status" -ne 0 ]
  run d4a_gen_remove_script ""
  [ "$status" -ne 0 ]
}

@test "remove script deletes a managed container and its files" {
  export STUB_DOCKER_INSPECT=true
  run bash -c "$(d4a_gen_remove_script demo)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"removed=demo"* ]]
  grep -q '^rm -f d4a-demo' "$STUB_LOG/docker.args"
  [ ! -e "$ROOT/artifacts/demo" ]
}

@test "remove script refuses a container it did not create" {
  export STUB_DOCKER_INSPECT=""
  run bash -c "$(d4a_gen_remove_script demo)"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not created by deploy4artifact"* ]]
  [ -d "$ROOT/artifacts/demo" ]
}

@test "list script filters on the managed and slug labels" {
  run d4a_gen_list_script
  [[ "$output" == *"--filter label=d4a.managed=true --filter label=d4a.slug"* ]]
}

@test "health script reports missing when there is no container" {
  export STUB_DOCKER_INSPECT_EXIT=1
  run bash -c "$(d4a_gen_health_script demo)"
  [ "$output" = "missing" ]
}
