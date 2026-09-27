#!/usr/bin/env bats
# SPDX-FileCopyrightText: Copyright (c) 2026 CuberHuber
# SPDX-License-Identifier: MIT

load '../helpers/stubs'

setup() {
  d4a_stubs_setup
  d4a_stubs_profile demo
  SRC="$(mktemp -d)"
  printf 'hi' > "$SRC/index.html"
}

teardown() {
  rm -rf "$SRC"
  d4a_stubs_teardown
}

@test "syncs with rsync over ssh using the keychain profile" {
  run bash "$SCRIPTS/deploy-vps.sh" demo "$SRC" /srv/site
  [ "$status" -eq 0 ]
  grep -qF -- "--delete-after" "$STUB_LOG/rsync.args"
  grep -qF "deploy@203.0.113.5:/srv/site/" "$STUB_LOG/rsync.args"
  grep -qF "StrictHostKeyChecking=accept-new" "$STUB_LOG/rsync.args"
}

@test "removes the temporary key file on exit" {
  run bash "$SCRIPTS/deploy-vps.sh" demo "$SRC" /srv/site
  key="$(grep -o '[^ ]*d4a-key\.[A-Za-z0-9]*' "$STUB_LOG/rsync.args" | head -1)"
  [ -n "$key" ]
  [ ! -e "$key" ]
}

@test "fails clearly for an unknown profile" {
  run bash "$SCRIPTS/deploy-vps.sh" ghost "$SRC" /srv/site
  [ "$status" -ne 0 ]
  [[ "$output" == *"no vps_ip stored"* ]]
}
