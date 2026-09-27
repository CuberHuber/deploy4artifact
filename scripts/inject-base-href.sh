#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2026 CuberHuber
# SPDX-License-Identifier: MIT
#
# Insert <base href="..."> right after the first <head> tag of an HTML file,
# so relative asset paths resolve under a path prefix. Idempotent.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib/common.sh
source "$DIR/lib/common.sh"

# shellcheck disable=SC2016  # an awk program; $0 is awk's, not the shell's
AWK_PROG='
BEGIN { done = 0; bad = 0 }
{
  if (!done && !bad) {
    low = tolower($0)
    if (match(low, /<head[ \t>]/) || match(low, /<head$/)) {
      rest = substr($0, RSTART)
      gt = index(rest, ">")
      if (gt > 0) {
        pos = RSTART + gt - 1
        $0 = substr($0, 1, pos) "<base href=\"" href "\">" substr($0, pos + 1)
        done = 1
      } else {
        bad = 1
      }
    }
  }
  print
}
END { if (bad) exit 2; if (!done) exit 3 }'

usage() {
  cat <<'EOF'
Usage: inject-base-href.sh <html-file> <href>

<href> must be an absolute path ending in "/", e.g. /d4a/a/my-slug/.
EOF
}

main() {
  [[ $# -eq 2 ]] || { usage; exit 2; }
  local file="$1" href="$2" tmp rc
  [[ -f "$file" ]] || d4a_die "HTML file not found: $file"
  [[ "$href" =~ ^/[A-Za-z0-9/_.-]*/$ && "$href" != *..* ]] || d4a_die "invalid base href: $href"
  if grep -qiE '<base[[:space:]>]' "$file"; then
    if grep -qF "<base href=\"$href\">" "$file"; then
      d4a_log "base href already set in $file"
      return 0
    fi
    d4a_die "$file already has a different <base> tag; refusing to override it"
  fi
  tmp="$(mktemp "${TMPDIR:-/tmp}/d4a-html.XXXXXX")"
  rc=0
  awk -v href="$href" "$AWK_PROG" "$file" > "$tmp" || rc=$?
  case "$rc" in
    0)
      cat "$tmp" > "$file"
      rm -f "$tmp"
      ;;
    2)
      rm -f "$tmp"
      d4a_die "the <head> tag in $file spans several lines; add <base href=\"$href\"> by hand"
      ;;
    *)
      rm -f "$tmp"
      d4a_die "no <head> tag found in $file; cannot inject <base href>"
      ;;
  esac
}

main "$@"
