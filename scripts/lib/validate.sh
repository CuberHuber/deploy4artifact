#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2026 CuberHuber
# SPDX-License-Identifier: MIT
#
# Input validation shared by every deploy4artifact script. Not meant to be
# executed directly; source scripts/lib/common.sh first for d4a_die.
set -euo pipefail

d4a_validate_profile_name() {
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$ ]] \
    || d4a_die "invalid profile name: '$1' (letters, digits, - and _, max 64 chars)"
}

d4a_validate_artifact_url() {
  [[ "$1" =~ ^https://claude\.ai/(code/)?artifact/[A-Za-z0-9_-]+/?$ ]] \
    || d4a_die "not a claude.ai artifact URL: $1"
}

d4a_validate_host() {
  local host="$1" octet
  if [[ "$host" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    for octet in ${host//./ }; do
      (( octet <= 255 )) || d4a_die "invalid VPS host/IP: $host"
    done
    return 0
  fi
  [[ "$host" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)*[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]] \
    || d4a_die "invalid VPS host/IP: $host"
}

d4a_validate_port() {
  [[ "$1" =~ ^[0-9]{1,5}$ ]] || d4a_die "invalid port: $1"
  (( 10#$1 >= 1 && 10#$1 <= 65535 )) || d4a_die "invalid port: $1"
}

d4a_validate_local_dest() {
  local path="$1"
  [[ "$path" = /* ]] || d4a_die "destination must be an absolute path: $path"
  case "$path" in
    *..*) d4a_die "destination must not contain '..': $path" ;;
    *) ;;
  esac
  case "$path" in
    "/" | "/etc" | "/etc/"* | "/bin" | "/bin/"* | "/sbin" | "/sbin/"* | \
    "/usr" | "/usr/"* | "/System" | "/System/"* | "/private/etc"* | \
    "/Library" | "/Library/"*)
      d4a_die "refusing to deploy into a system path: $path" ;;
    *) ;;
  esac
}

d4a_validate_remote_path() {
  local path="$1"
  [[ "$path" = /* ]] || d4a_die "remote path must be absolute: $path"
  case "$path" in
    *..*) d4a_die "remote path must not contain '..': $path" ;;
    *) ;;
  esac
  case "$path" in
    "/" | "/etc" | "/etc/"* | "/bin" | "/bin/"* | "/sbin" | "/sbin/"* | \
    "/boot" | "/boot/"*)
      d4a_die "refusing to deploy into a system path: $path" ;;
    *) ;;
  esac
}
