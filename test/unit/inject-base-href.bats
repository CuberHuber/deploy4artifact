#!/usr/bin/env bats
# SPDX-FileCopyrightText: Copyright (c) 2026 CuberHuber
# SPDX-License-Identifier: MIT

setup() {
  SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../scripts" && pwd)/inject-base-href.sh"
  WORK="$(mktemp -d)"
  HTML="$WORK/index.html"
}

teardown() {
  rm -rf "$WORK"
}

@test "inserts base right after <head>" {
  printf '<html><head><title>x</title></head><body></body></html>\n' > "$HTML"
  run bash "$SCRIPT" "$HTML" /d4a/a/demo/
  [ "$status" -eq 0 ]
  grep -qF '<head><base href="/d4a/a/demo/"><title>' "$HTML"
}

@test "handles an uppercase head tag with attributes" {
  printf '<HTML>\n<HEAD lang="en">\n<title>x</title>\n' > "$HTML"
  run bash "$SCRIPT" "$HTML" /d4a/a/demo/
  [ "$status" -eq 0 ]
  grep -qF '<HEAD lang="en"><base href="/d4a/a/demo/">' "$HTML"
}

@test "does not mistake <header> for <head>" {
  printf '<!-- <header> -->\n<head>\n<title>x</title>\n' > "$HTML"
  run bash "$SCRIPT" "$HTML" /d4a/a/demo/
  [ "$status" -eq 0 ]
  grep -qF '<!-- <header> -->' "$HTML"
  grep -qF '<head><base href="/d4a/a/demo/">' "$HTML"
}

@test "is idempotent" {
  printf '<head></head>\n' > "$HTML"
  bash "$SCRIPT" "$HTML" /d4a/a/demo/
  run bash "$SCRIPT" "$HTML" /d4a/a/demo/
  [ "$status" -eq 0 ]
  [ "$(grep -o 'base href' "$HTML" | wc -l | tr -d ' ')" -eq 1 ]
}

@test "refuses to override a different base tag and leaves the file untouched" {
  printf '<head><base href="/other/"></head>\n' > "$HTML"
  cp "$HTML" "$WORK/before"
  run bash "$SCRIPT" "$HTML" /d4a/a/demo/
  [ "$status" -ne 0 ]
  cmp -s "$HTML" "$WORK/before"
}

@test "fails clearly when there is no head tag" {
  printf '<body><header>h</header></body>\n' > "$HTML"
  run bash "$SCRIPT" "$HTML" /d4a/a/demo/
  [ "$status" -ne 0 ]
  [[ "$output" == *"no <head> tag"* ]]
}

@test "fails when the head tag spans lines" {
  printf '<head\n  lang="en">\n' > "$HTML"
  run bash "$SCRIPT" "$HTML" /d4a/a/demo/
  [ "$status" -ne 0 ]
  [[ "$output" == *"spans several lines"* ]]
}

@test "rejects an href that could break out of the attribute" {
  printf '<head></head>\n' > "$HTML"
  run bash "$SCRIPT" "$HTML" '/x/"onload="alert(1)/'
  [ "$status" -ne 0 ]
}
