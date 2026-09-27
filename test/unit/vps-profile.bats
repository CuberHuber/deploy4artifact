#!/usr/bin/env bats
# SPDX-FileCopyrightText: Copyright (c) 2026 CuberHuber
# SPDX-License-Identifier: MIT

load '../helpers/stubs'

setup() {
  d4a_stubs_setup
  d4a_stubs_profile demo
}

teardown() {
  d4a_stubs_teardown
}

@test "show marks the site fields as not set on a fresh profile" {
  run bash "$SCRIPTS/vps-profile.sh" show demo
  [ "$status" -eq 0 ]
  [[ "$output" == *"domain: (not set)"* ]]
}

@test "set-site stores domain and email in the keychain and show prints them" {
  run bash "$SCRIPTS/vps-profile.sh" set-site demo d4a.example.com ops@example.com
  [ "$status" -eq 0 ]
  [ "$(cat "$KC_DIR/deploy4artifact:demo/site_domain")" = "d4a.example.com" ]
  [ "$(cat "$KC_DIR/deploy4artifact:demo/acme_email")" = "ops@example.com" ]
  run bash "$SCRIPTS/vps-profile.sh" show demo
  [[ "$output" == *"domain: d4a.example.com"* ]]
  [[ "$output" == *"acme email: ops@example.com"* ]]
}

@test "set-site rejects an IP address and writes nothing" {
  run bash "$SCRIPTS/vps-profile.sh" set-site demo 203.0.113.5 ops@example.com
  [ "$status" -ne 0 ]
  [ ! -e "$KC_DIR/deploy4artifact:demo/site_domain" ]
}

@test "set-site fails for an unknown profile" {
  run bash "$SCRIPTS/vps-profile.sh" set-site ghost d4a.example.com ops@example.com
  [ "$status" -ne 0 ]
  [[ "$output" == *"no such profile"* ]]
}

@test "remove deletes the site fields too" {
  bash "$SCRIPTS/vps-profile.sh" set-site demo d4a.example.com ops@example.com
  run bash "$SCRIPTS/vps-profile.sh" remove demo
  [ "$status" -eq 0 ]
  [ ! -e "$KC_DIR/deploy4artifact:demo/site_domain" ]
  [ ! -e "$KC_DIR/deploy4artifact:demo/acme_email" ]
}
