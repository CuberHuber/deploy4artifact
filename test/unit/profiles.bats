#!/usr/bin/env bats
# SPDX-FileCopyrightText: Copyright (c) 2026 CuberHuber
# SPDX-License-Identifier: MIT

setup() {
  DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../scripts" && pwd)"
  D4A_HOME="$(mktemp -d)"
  export D4A_HOME
  # shellcheck source=/dev/null
  source "$DIR/lib/common.sh"
  # shellcheck source=/dev/null
  source "$DIR/lib/profiles.sh"
}

teardown() {
  rm -rf "$D4A_HOME"
}

@test "registry starts empty" {
  run cat "$(d4a_profiles_registry)"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "adding a profile name records it" {
  d4a_profile_add_name "prod"
  run d4a_profile_exists "prod"
  [ "$status" -eq 0 ]
}

@test "adding the same name twice does not duplicate it" {
  d4a_profile_add_name "prod"
  d4a_profile_add_name "prod"
  run wc -l < "$(d4a_profiles_registry)"
  [ "${output// /}" -eq 1 ]
}

@test "removing a profile name drops it" {
  d4a_profile_add_name "prod"
  d4a_profile_remove_name "prod"
  run d4a_profile_exists "prod"
  [ "$status" -ne 0 ]
}

@test "registry file is created with mode 600" {
  d4a_profiles_registry >/dev/null
  run stat -f '%Lp' "$D4A_HOME/profiles.list"
  if [ "$status" -ne 0 ]; then
    run stat -c '%a' "$D4A_HOME/profiles.list"
  fi
  [ "$output" = "600" ]
}
