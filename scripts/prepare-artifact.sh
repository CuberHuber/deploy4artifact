#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2026 CuberHuber
# SPDX-License-Identifier: MIT
#
# Prepare a fetched artifact for path-prefix hosting: copy it to a fresh
# staging directory, zip the untouched files into the reserved .d4a/
# directory for download, and inject <base href> into the entry HTML.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib/common.sh
source "$DIR/lib/common.sh"
# shellcheck source=./lib/validate.sh
source "$DIR/lib/validate.sh"

usage() {
  cat <<'EOF'
Usage: prepare-artifact.sh <fetched-dir> <slug> <staging-dir>

Copies <fetched-dir> into <staging-dir> (which must be new or empty),
writes <staging-dir>/.d4a/download.zip from the untouched fetched files,
and injects <base href="/d4a/a/<slug>/"> into the entry HTML. An entry
other than index.html is also copied to index.html so nginx serves it at
the root. Symlinks go into the zip as links, never as the files they point
to. Prints "entry=<file>" on success.
EOF
}

find_entry() {
  local src="$1" candidates count
  if [[ -f "$src/index.html" ]]; then
    printf 'index.html'
    return 0
  fi
  candidates="$(cd "$src" && find . -maxdepth 1 -type f \( -iname '*.html' -o -iname '*.htm' \) \
    | sed 's|^\./||' | sort)"
  count="$(printf '%s' "$candidates" | grep -c . || true)"
  case "$count" in
    1) printf '%s' "$candidates" ;;
    0) d4a_die "no HTML entry file at the top level of $src" ;;
    *) d4a_die "cannot pick an entry HTML: no index.html and $count top-level HTML files: $(printf '%s' "$candidates" | tr '\n' ' ')" ;;
  esac
}

main() {
  [[ $# -eq 3 ]] || { usage; exit 2; }
  local src="$1" slug="$2" staging="$3" src_abs staging_abs entry
  d4a_validate_slug "$slug"
  [[ -d "$src" ]] || d4a_die "fetched artifact directory not found: $src"
  [[ ! -e "$src/.d4a" ]] \
    || d4a_die "the artifact contains a .d4a entry, which deploy4artifact reserves for its own files; refusing to overwrite it"
  d4a_require_cmd zip
  if [[ -e "$staging" ]]; then
    [[ -d "$staging" && -z "$(find "$staging" -mindepth 1 -maxdepth 1 -print -quit)" ]] \
      || d4a_die "staging directory must be new or empty: $staging"
  fi
  src_abs="$(cd "$src" && pwd -P)"
  local probe rest staging_resolved
  probe="$staging"
  rest=""
  while [[ ! -d "$probe" ]]; do
    rest="/$(basename "$probe")$rest"
    probe="$(dirname "$probe")"
  done
  staging_resolved="$(cd "$probe" && pwd -P)$rest"
  case "$staging_resolved/" in
    "$src_abs/"*) d4a_die "the staging directory must not be inside the fetched artifact" ;;
    *) ;;
  esac
  entry="$(find_entry "$src_abs")"
  mkdir -p "$staging"
  staging_abs="$(cd "$staging" && pwd -P)"
  cp -R "$src_abs"/. "$staging_abs"/
  mkdir -p "$staging_abs/.d4a"
  (cd "$src_abs" && zip -qrXy "$staging_abs/.d4a/download.zip" .)
  bash "$DIR/inject-base-href.sh" "$staging_abs/$entry" "/d4a/a/$slug/"
  if [[ "$entry" != "index.html" ]]; then
    # nginx serves only index.html at the directory root.
    cp "$staging_abs/$entry" "$staging_abs/index.html"
  fi
  printf 'entry=%s\n' "$entry"
}

main "$@"
