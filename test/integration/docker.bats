#!/usr/bin/env bats
# SPDX-FileCopyrightText: Copyright (c) 2026 CuberHuber
# SPDX-License-Identifier: MIT

setup() {
  command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1 || skip "Docker is not available"
  SCRIPTS="$(cd "$BATS_TEST_DIRNAME/../../scripts" && pwd)"
  LIBS="source '$SCRIPTS/lib/common.sh'; source '$SCRIPTS/lib/validate.sh'; source '$SCRIPTS/lib/remote-scripts.sh'"
  ROOT="$(mktemp -d)"
  NET="d4a-it-net-$$"
  docker network create --internal "$NET" >/dev/null
  if ! docker network inspect d4a-internal >/dev/null 2>&1; then
    docker network create --internal d4a-internal >/dev/null
    touch "$ROOT/.created-d4a-internal"
  fi
}

teardown() {
  docker rm -f d4a-it-web d4a-itdemo d4a-itfake >/dev/null 2>&1 || true
  docker network rm "$NET" >/dev/null 2>&1 || true
  if [ -e "$ROOT/.created-d4a-internal" ]; then
    docker network rm d4a-internal >/dev/null 2>&1 || true
  fi
  rm -rf "$ROOT"
}

@test "a container on an --internal network has no route to the internet" {
  run docker run --rm --network "$NET" alpine:3 wget -q -T 5 -O /dev/null http://1.1.1.1/
  [ "$status" -ne 0 ]
}

@test "containers on the same --internal network can reach each other" {
  docker run -d --name d4a-it-web --network "$NET" nginx:stable-alpine >/dev/null
  run docker run --rm --network "$NET" alpine:3 sh -c 'for i in 1 2 3 4 5; do wget -q -T 2 -O - http://d4a-it-web/ && exit 0; sleep 1; done; exit 1'
  [ "$status" -eq 0 ]
  [[ "$output" == *"nginx"* ]]
}

@test "the generated run script serves the artifact on d4a-internal and gets healthy" {
  mkdir -p "$ROOT/artifacts/itdemo"
  printf '<html><head></head><body>hello-d4a</body></html>' > "$ROOT/artifacts/itdemo/index.html"
  run env D4A_REMOTE_ROOT="$ROOT" D4A_HEALTH_WAIT=60 bash -c "$LIBS; d4a_gen_run_script itdemo d4a.example.com | bash"
  [ "$status" -eq 0 ]
  [[ "$output" == *"container=healthy"* ]]
  run docker inspect -f '{{index .Config.Labels "traefik.enable"}} {{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{end}}' d4a-itdemo
  [ "$output" = "true d4a-internal" ]
  run docker run --rm --network d4a-internal alpine:3 wget -q -T 5 -O - http://d4a-itdemo/
  [[ "$output" == *"hello-d4a"* ]]
}

@test "the generated remove script deletes a managed container and its files" {
  mkdir -p "$ROOT/artifacts/itdemo"
  printf '<html><head></head><body>x</body></html>' > "$ROOT/artifacts/itdemo/index.html"
  env D4A_REMOTE_ROOT="$ROOT" D4A_HEALTH_WAIT=60 bash -c "$LIBS; d4a_gen_run_script itdemo d4a.example.com | bash"
  run env D4A_REMOTE_ROOT="$ROOT" bash -c "$LIBS; d4a_gen_remove_script itdemo | bash"
  [ "$status" -eq 0 ]
  run docker inspect d4a-itdemo
  [ "$status" -ne 0 ]
  [ ! -e "$ROOT/artifacts/itdemo" ]
}

@test "the generated remove script refuses a container it did not create" {
  docker run -d --name d4a-itfake nginx:stable-alpine >/dev/null
  mkdir -p "$ROOT/artifacts/itfake"
  run env D4A_REMOTE_ROOT="$ROOT" bash -c "$LIBS; d4a_gen_remove_script itfake | bash"
  [ "$status" -ne 0 ]
  docker inspect d4a-itfake >/dev/null
  [ -d "$ROOT/artifacts/itfake" ]
}
