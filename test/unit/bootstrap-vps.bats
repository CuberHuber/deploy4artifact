#!/usr/bin/env bats
# SPDX-FileCopyrightText: Copyright (c) 2026 CuberHuber
# SPDX-License-Identifier: MIT

load '../helpers/stubs'

setup() {
  d4a_stubs_setup
}

teardown() {
  d4a_stubs_teardown
}

@test "check runs the check script and passes its report through" {
  d4a_stubs_profile demo
  printf 'docker=ok\nsudo=ok\ntraefik=running\n' > "$STUB_LOG/ssh.reply.1"
  run bash "$SCRIPTS/bootstrap-vps.sh" demo check
  [ "$status" -eq 0 ]
  [[ "$output" == *"traefik=running"* ]]
  grep -qF 'echo "docker=$docker_state"' "$STUB_LOG/ssh.stdin.1"
}

@test "install-docker sends the package-manager install script" {
  d4a_stubs_profile demo
  run bash "$SCRIPTS/bootstrap-vps.sh" demo install-docker
  [ "$status" -eq 0 ]
  grep -qF 'apt-get install -y docker.io' "$STUB_LOG/ssh.stdin.1"
}

@test "ensure-proxy without an ACME email fails before connecting" {
  d4a_stubs_profile demo
  run bash "$SCRIPTS/bootstrap-vps.sh" demo ensure-proxy
  [ "$status" -ne 0 ]
  [[ "$output" == *"set-site"* ]]
  [ ! -e "$STUB_LOG/ssh.args" ]
}

@test "ensure-proxy sends the proxy script with the profile's email" {
  d4a_stubs_profile demo d4a.example.com ops@example.com
  printf 'traefik=started\n' > "$STUB_LOG/ssh.reply.1"
  run bash "$SCRIPTS/bootstrap-vps.sh" demo ensure-proxy
  [ "$status" -eq 0 ]
  grep -qF "ACME_EMAIL='ops@example.com'" "$STUB_LOG/ssh.stdin.1"
}

@test "an unknown action exits 2" {
  d4a_stubs_profile demo
  run bash "$SCRIPTS/bootstrap-vps.sh" demo destroy
  [ "$status" -eq 2 ]
}
