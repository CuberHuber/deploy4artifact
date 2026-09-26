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
  source "$DIR/lib/validate.sh"
  # shellcheck source=/dev/null
  source "$DIR/lib/registry.sh"
}

teardown() {
  rm -rf "$D4A_HOME"
}

@test "registry starts empty and private" {
  run cat "$(d4a_reg_path)"
  [ -z "$output" ]
  [ "$(ls -l "$D4A_HOME/deployments.list" | cut -c1-10)" = "-rw-------" ]
}

@test "put then get returns the tab-separated line" {
  d4a_reg_put demo prod 2026-09-26T10:00:00Z
  run d4a_reg_get demo
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'demo\tprod\t2026-09-26T10:00:00Z')" ]
}

@test "put replaces an existing slug instead of duplicating it" {
  d4a_reg_put demo prod 2026-09-26T10:00:00Z
  d4a_reg_put demo prod 2026-09-26T11:00:00Z
  [ "$(grep -c '^demo' "$(d4a_reg_path)")" -eq 1 ]
  run d4a_reg_get demo
  [[ "$output" == *"11:00:00Z" ]]
  [ "$(ls -l "$D4A_HOME/deployments.list" | cut -c1-10)" = "-rw-------" ]
}

@test "get of a missing slug exits 1" {
  run d4a_reg_get nope
  [ "$status" -eq 1 ]
}

@test "remove drops only that slug" {
  d4a_reg_put demo prod 2026-09-26T10:00:00Z
  d4a_reg_put other prod 2026-09-26T10:00:00Z
  d4a_reg_remove demo
  run d4a_reg_exists demo
  [ "$status" -ne 0 ]
  run d4a_reg_exists other
  [ "$status" -eq 0 ]
}

@test "put rejects an invalid slug or timestamp" {
  run d4a_reg_put "Bad Slug" prod 2026-09-26T10:00:00Z
  [ "$status" -ne 0 ]
  run d4a_reg_put demo prod yesterday
  [ "$status" -ne 0 ]
}
