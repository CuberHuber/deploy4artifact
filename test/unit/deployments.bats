#!/usr/bin/env bats
# SPDX-FileCopyrightText: Copyright (c) 2026 CuberHuber
# SPDX-License-Identifier: MIT

load '../helpers/stubs'

setup() {
  d4a_stubs_setup
  d4a_stubs_profile demo d4a.example.com ops@example.com
  REG="$D4A_HOME/deployments.list"
}

teardown() {
  d4a_stubs_teardown
}

seed() {
  printf 'demo\tdemo\t2026-09-26T10:00:00Z\nother\tdemo\t2026-09-26T11:00:00Z\n' > "$REG"
}

@test "list with no deployments says so" {
  run bash "$SCRIPTS/deployments.sh" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"no deployments recorded"* ]]
}

@test "list joins the registry with container status, one SSH call per profile" {
  seed
  printf 'demo\tUp 2 hours (healthy)\n' > "$STUB_LOG/ssh.reply.1"
  run bash "$SCRIPTS/deployments.sh" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"demo"*"Up 2 hours (healthy)"* ]]
  [[ "$output" == *"other"*"missing"* ]]
  [ "$(cat "$STUB_LOG/ssh.count")" -eq 1 ]
}

@test "list degrades to unreachable when SSH fails" {
  seed
  printf '255' > "$STUB_LOG/ssh.exit.1"
  run bash "$SCRIPTS/deployments.sh" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"demo"*"unreachable"* ]]
}

@test "health is ok when the container is healthy and HTTPS answers 200" {
  seed
  printf 'running healthy\n' > "$STUB_LOG/ssh.reply.1"
  run bash "$SCRIPTS/deployments.sh" health demo
  [ "$status" -eq 0 ]
  [[ "$output" == *"overall=ok"* ]]
  grep -qF "https://d4a.example.com/d4a/a/demo/" "$STUB_LOG/curl.args"
}

@test "health is degraded when the proxy path fails" {
  seed
  printf 'running healthy\n' > "$STUB_LOG/ssh.reply.1"
  export STUB_CURL_CODE=502
  run bash "$SCRIPTS/deployments.sh" health demo
  [ "$status" -eq 0 ]
  [[ "$output" == *"https=502"* && "$output" == *"overall=degraded"* ]]
}

@test "health of an unknown slug fails" {
  run bash "$SCRIPTS/deployments.sh" health ghost
  [ "$status" -ne 0 ]
  [[ "$output" == *"no deployment named 'ghost'"* ]]
}

@test "remove deletes remotely and then forgets the slug" {
  seed
  printf 'removed=demo\n' > "$STUB_LOG/ssh.reply.1"
  run bash "$SCRIPTS/deployments.sh" remove demo
  [ "$status" -eq 0 ]
  grep -qF "SLUG='demo'" "$STUB_LOG/ssh.stdin.1"
  [ -z "$(grep '^demo' "$REG" || true)" ]
  grep -q '^other' "$REG"
}

@test "remove keeps the registry entry when the remote side fails" {
  seed
  printf '1' > "$STUB_LOG/ssh.exit.1"
  run bash "$SCRIPTS/deployments.sh" remove demo
  [ "$status" -ne 0 ]
  grep -q '^demo' "$REG"
}

@test "suggest-slug sanitizes text and reports whether it is taken" {
  run bash "$SCRIPTS/deployments.sh" suggest-slug "My_Artifact 01"
  [ "$output" = "$(printf 'slug=my-artifact-01\ntaken=no')" ]
  printf 'my-artifact-01\tdemo\t2026-09-26T10:00:00Z\n' > "$REG"
  run bash "$SCRIPTS/deployments.sh" suggest-slug "My_Artifact 01"
  [[ "$output" == *"taken=yes"* ]]
}
