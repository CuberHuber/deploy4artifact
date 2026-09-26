#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2026 CuberHuber
# SPDX-License-Identifier: MIT
#
# Local deployment registry at $D4A_HOME/deployments.list: one tab-separated
# "slug profile deployed_at" line per deployed slug. Holds no secrets. Not
# meant to be executed directly; source common.sh and validate.sh first.
set -euo pipefail

d4a_reg_path() {
  mkdir -p "$D4A_HOME"
  chmod 700 "$D4A_HOME"
  touch "$D4A_HOME/deployments.list"
  chmod 600 "$D4A_HOME/deployments.list"
  printf '%s' "$D4A_HOME/deployments.list"
}

d4a_reg_get() {
  local reg
  reg="$(d4a_reg_path)"
  awk -F'\t' -v s="$1" '$1 == s { print; found = 1 } END { exit found ? 0 : 1 }' "$reg"
}

d4a_reg_exists() {
  d4a_reg_get "$1" >/dev/null
}

_d4a_reg_without() {
  local reg tmp
  reg="$(d4a_reg_path)"
  tmp="$(mktemp "$D4A_HOME/.deployments.XXXXXX")"
  awk -F'\t' -v s="$1" '$1 != s' "$reg" > "$tmp"
  printf '%s' "$tmp"
}

d4a_reg_put() {
  local slug="$1" profile="$2" ts="$3" reg tmp
  d4a_validate_slug "$slug"
  d4a_validate_profile_name "$profile"
  [[ "$ts" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] \
    || d4a_die "invalid timestamp: $ts"
  reg="$(d4a_reg_path)"
  tmp="$(_d4a_reg_without "$slug")"
  printf '%s\t%s\t%s\n' "$slug" "$profile" "$ts" >> "$tmp"
  mv "$tmp" "$reg"
  chmod 600 "$reg"
}

d4a_reg_remove() {
  local reg tmp
  reg="$(d4a_reg_path)"
  tmp="$(_d4a_reg_without "$1")"
  mv "$tmp" "$reg"
  chmod 600 "$reg"
}
