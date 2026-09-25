#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2026 CuberHuber
# SPDX-License-Identifier: MIT
#
# Shared helpers sourced by every deploy4artifact script. Not meant to be
# executed directly.
set -euo pipefail

D4A_HOME="${D4A_HOME:-$HOME/.deploy4artifact}"
D4A_KNOWN_HOSTS="$D4A_HOME/known_hosts"
export D4A_HOME D4A_KNOWN_HOSTS

d4a_log() { printf '[deploy4artifact] %s\n' "$*" >&2; }
d4a_die() { d4a_log "ERROR: $*"; exit 1; }

d4a_require_cmd() {
  command -v "$1" >/dev/null 2>&1 || d4a_die "required command not found: $1"
}
