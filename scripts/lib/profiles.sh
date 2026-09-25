#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2026 CuberHuber
# SPDX-License-Identifier: MIT
#
# Profile name registry for deploy4artifact. Stores only profile labels
# (never connection details or secrets) at $D4A_HOME/profiles.list. Not
# meant to be executed directly.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$DIR/common.sh"

d4a_profiles_registry() {
  mkdir -p "$D4A_HOME"
  chmod 700 "$D4A_HOME"
  touch "$D4A_HOME/profiles.list"
  chmod 600 "$D4A_HOME/profiles.list"
  printf '%s' "$D4A_HOME/profiles.list"
}

d4a_profile_exists() {
  local name="$1" registry
  registry="$(d4a_profiles_registry)"
  grep -qxF "$name" "$registry"
}

d4a_profile_add_name() {
  local name="$1" registry
  registry="$(d4a_profiles_registry)"
  d4a_profile_exists "$name" || printf '%s\n' "$name" >> "$registry"
}

d4a_profile_remove_name() {
  local name="$1" registry tmp
  registry="$(d4a_profiles_registry)"
  tmp="$(mktemp "${TMPDIR:-/tmp}/d4a-registry.XXXXXX")"
  grep -vxF "$name" "$registry" > "$tmp" || true
  mv "$tmp" "$registry"
  chmod 600 "$registry"
}
