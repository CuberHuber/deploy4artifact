#!/usr/bin/env bats
# SPDX-FileCopyrightText: Copyright (c) 2026 CuberHuber
# SPDX-License-Identifier: MIT

load '../helpers/stubs'

setup() {
  d4a_stubs_setup
  d4a_stubs_profile demo d4a.example.com ops@example.com
  STAGE="$(mktemp -d)"
  printf '<head></head>' > "$STAGE/index.html"
  mkdir -p "$STAGE/.d4a"
  printf 'zip' > "$STAGE/.d4a/download.zip"
  printf 'docker=ok\nsudo=ok\ntraefik=running\n' > "$STUB_LOG/ssh.reply.1"
  printf 'container=healthy\n' > "$STUB_LOG/ssh.reply.2"
}

teardown() {
  rm -rf "$STAGE"
  d4a_stubs_teardown
}

@test "deploys, prints both URLs, and records the slug" {
  run bash "$SCRIPTS/deploy.sh" demo "$STAGE" demo
  [ "$status" -eq 0 ]
  [[ "$output" == *"url=https://d4a.example.com/d4a/a/demo/"* ]]
  [[ "$output" == *"download=https://d4a.example.com/d4a/a/demo/.d4a/download.zip"* ]]
  grep -qF "deploy@203.0.113.5:/srv/deploy4artifact/artifacts/demo/" "$STUB_LOG/rsync.args"
  grep -qF -- "--delete-after" "$STUB_LOG/rsync.args"
  grep -qF "SLUG='demo'" "$STUB_LOG/ssh.stdin.2"
  grep -q "$(printf '^demo\tdemo\t')" "$D4A_HOME/deployments.list"
}

@test "stops before syncing when the proxy is not running" {
  printf 'docker=ok\nsudo=ok\ntraefik=missing\n' > "$STUB_LOG/ssh.reply.1"
  run bash "$SCRIPTS/deploy.sh" demo "$STAGE" demo
  [ "$status" -ne 0 ]
  [[ "$output" == *"ensure-proxy"* ]]
  [ ! -e "$STUB_LOG/rsync.args" ]
}

@test "stops before syncing when the SSH user cannot reach Docker" {
  printf 'docker=no-access\nsudo=no\ntraefik=missing\n' > "$STUB_LOG/ssh.reply.1"
  run bash "$SCRIPTS/deploy.sh" demo "$STAGE" demo
  [ "$status" -ne 0 ]
  [[ "$output" == *"docker=no-access"* && "$output" == *"bootstrap-vps.sh"* ]]
  [ ! -e "$STUB_LOG/rsync.args" ]
}

@test "refuses a directory that was not prepared" {
  rm -rf "$STAGE/.d4a"
  run bash "$SCRIPTS/deploy.sh" demo "$STAGE" demo
  [ "$status" -ne 0 ]
  [[ "$output" == *"prepare-artifact.sh"* ]]
  [ ! -e "$STUB_LOG/ssh.args" ]
}

@test "does not record a deploy whose container failed" {
  printf '1' > "$STUB_LOG/ssh.exit.2"
  run bash "$SCRIPTS/deploy.sh" demo "$STAGE" demo
  [ "$status" -ne 0 ]
  [ -z "$(grep '^demo' "$D4A_HOME/deployments.list" 2>/dev/null || true)" ]
}

@test "fails with a set-site hint when the profile has no domain" {
  rm -f "$KC_DIR/deploy4artifact:demo/site_domain"
  run bash "$SCRIPTS/deploy.sh" demo "$STAGE" demo
  [ "$status" -ne 0 ]
  [[ "$output" == *"set-site"* ]]
}
