#!/usr/bin/env bats
# SPDX-FileCopyrightText: Copyright (c) 2026 CuberHuber
# SPDX-License-Identifier: MIT

setup() {
  SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../scripts" && pwd)/prepare-artifact.sh"
  WORK="$(mktemp -d)"
  SRC="$WORK/fetched"
  STAGE="$WORK/stage"
  mkdir -p "$SRC"
}

teardown() {
  rm -rf "$WORK"
}

@test "copies files, injects base href into the entry, and zips the untouched files" {
  printf '<html><head></head><body>hi</body></html>\n' > "$SRC/index.html"
  printf 'body{}' > "$SRC/style.css"
  run bash "$SCRIPT" "$SRC" demo "$STAGE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"entry=index.html"* ]]
  grep -qF '<base href="/d4a/a/demo/">' "$STAGE/index.html"
  [ -f "$STAGE/style.css" ]
  unzip -l "$STAGE/.d4a/download.zip" | grep -q ' index.html$'
  unzip -l "$STAGE/.d4a/download.zip" | grep -q ' style.css$'
  [ -z "$(unzip -p "$STAGE/.d4a/download.zip" index.html | grep 'base href' || true)" ]
  [ -z "$(grep 'base href' "$SRC/index.html" || true)" ]
}

@test "keeps file names with spaces in the copy and the zip" {
  printf '<head></head>\n' > "$SRC/index.html"
  printf 'x' > "$SRC/my notes.txt"
  run bash "$SCRIPT" "$SRC" demo "$STAGE"
  [ "$status" -eq 0 ]
  [ -f "$STAGE/my notes.txt" ]
  unzip -l "$STAGE/.d4a/download.zip" | grep -q ' my notes.txt$'
}

@test "uses the only top-level HTML file when there is no index.html" {
  printf '<head></head>\n' > "$SRC/page.html"
  run bash "$SCRIPT" "$SRC" demo "$STAGE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"entry=page.html"* ]]
  grep -qF '<base href="/d4a/a/demo/">' "$STAGE/page.html"
}

@test "refuses to guess between several top-level HTML files and names them" {
  printf '<head></head>\n' > "$SRC/a.html"
  printf '<head></head>\n' > "$SRC/b.html"
  run bash "$SCRIPT" "$SRC" demo "$STAGE"
  [ "$status" -ne 0 ]
  [[ "$output" == *"a.html"* && "$output" == *"b.html"* ]]
}

@test "refuses an artifact that already contains .d4a" {
  printf '<head></head>\n' > "$SRC/index.html"
  mkdir "$SRC/.d4a"
  run bash "$SCRIPT" "$SRC" demo "$STAGE"
  [ "$status" -ne 0 ]
  [[ "$output" == *"reserves"* ]]
}

@test "refuses a non-empty staging directory" {
  printf '<head></head>\n' > "$SRC/index.html"
  mkdir -p "$STAGE"
  printf 'x' > "$STAGE/leftover"
  run bash "$SCRIPT" "$SRC" demo "$STAGE"
  [ "$status" -ne 0 ]
}

@test "refuses a staging directory inside the fetched artifact" {
  printf '<head></head>\n' > "$SRC/index.html"
  run bash "$SCRIPT" "$SRC" demo "$SRC/stage"
  [ "$status" -ne 0 ]
}

@test "rejects an invalid slug before touching anything" {
  printf '<head></head>\n' > "$SRC/index.html"
  run bash "$SCRIPT" "$SRC" "../x" "$STAGE"
  [ "$status" -ne 0 ]
  [ ! -e "$STAGE" ]
}
