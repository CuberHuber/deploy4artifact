#!/usr/bin/env bats
# SPDX-FileCopyrightText: Copyright (c) 2026 CuberHuber
# SPDX-License-Identifier: MIT

load '../helpers/stubs'

setup() {
  d4a_stubs_setup
  # shellcheck source=/dev/null
  source "$SCRIPTS/lib/common.sh"
  # shellcheck source=/dev/null
  source "$SCRIPTS/lib/validate.sh"
  # shellcheck source=/dev/null
  source "$SCRIPTS/lib/remote-scripts.sh"
}

teardown() {
  d4a_stubs_teardown
}

@test "every bootstrap script is valid bash" {
  d4a_gen_check_script | bash -n
  d4a_gen_install_docker_script | bash -n
  d4a_gen_proxy_script ops@example.com | bash -n
}

@test "check reports ok and a running proxy when Docker answers" {
  export STUB_DOCKER_PS="abc123"
  run bash -c "$(d4a_gen_check_script)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"docker=ok"* ]]
  [[ "$output" == *"traefik=running"* ]]
}

@test "check reports no-access when the user cannot talk to Docker" {
  export STUB_DOCKER_INFO_EXIT=1
  run bash -c "$(d4a_gen_check_script)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"docker=no-access"* ]]
  [[ "$output" == *"traefik=missing"* ]]
}

@test "install script uses the package manager and never pipes a download into a shell" {
  run d4a_gen_install_docker_script
  [[ "$output" == *"apt-get install -y docker.io"* ]]
  [[ "$output" == *"dnf install -y docker"* ]]
  [[ "$output" != *"| sh"* && "$output" != *"| bash"* ]]
}

@test "proxy script embeds the validated email and keeps artifacts off the internet" {
  run d4a_gen_proxy_script ops@example.com
  [ "$status" -eq 0 ]
  [[ "$output" == *"ACME_EMAIL='ops@example.com'"* ]]
  [[ "$output" == *"D4A_ROOT='/srv/deploy4artifact'"* ]]
  [[ "$output" == *"docker network create --internal d4a-internal"* ]]
  [[ "$output" == *"--providers.docker.exposedbydefault=false"* ]]
  [[ "$output" == *"docker network connect d4a-internal d4a-traefik"* ]]
}

@test "proxy script refuses an invalid email" {
  run d4a_gen_proxy_script "x'; rm -rf /; '"
  [ "$status" -ne 0 ]
}

@test "a remote root containing .. is refused" {
  D4A_REMOTE_ROOT="/srv/../etc"
  run d4a_gen_proxy_script ops@example.com
  [ "$status" -ne 0 ]
}
