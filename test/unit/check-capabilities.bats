#!/usr/bin/env bats
# SPDX-FileCopyrightText: Copyright (c) 2026 CuberHuber
# SPDX-License-Identifier: MIT

setup() {
  SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../scripts" && pwd)/check-capabilities.sh"
  SRC="$(mktemp -d)"
}

teardown() {
  rm -rf "$SRC"
}

@test "clean artifact exits 0 with no output" {
  printf '<html><body>hi</body></html>' > "$SRC/index.html"
  run bash "$SCRIPT" "$SRC"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "window.claude call in HTML exits 3 and names the file" {
  printf '<script>window.claude.complete("x")</script>' > "$SRC/index.html"
  run bash "$SCRIPT" "$SRC"
  [ "$status" -eq 3 ]
  [ "$output" = "index.html" ]
}

@test "bracket access in a nested JS file is detected" {
  mkdir -p "$SRC/js"
  printf "const c = window['claude'];" > "$SRC/js/app.js"
  run bash "$SCRIPT" "$SRC"
  [ "$status" -eq 3 ]
  [ "$output" = "js/app.js" ]
}

@test "a longer identifier is not a false positive" {
  printf 'window.claudette = 1;' > "$SRC/app.js"
  run bash "$SCRIPT" "$SRC"
  [ "$status" -eq 0 ]
}

@test "non-script files are ignored" {
  printf '/* window.claude */' > "$SRC/style.css"
  run bash "$SCRIPT" "$SRC"
  [ "$status" -eq 0 ]
}

@test "missing directory fails" {
  run bash "$SCRIPT" "$SRC/nope"
  [ "$status" -eq 1 ]
}
