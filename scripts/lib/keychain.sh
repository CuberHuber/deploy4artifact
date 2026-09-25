#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2026 CuberHuber
# SPDX-License-Identifier: MIT
#
# OS keychain backend for deploy4artifact. Not meant to be executed
# directly; source scripts/lib/common.sh first for d4a_die.
set -euo pipefail

d4a_kc_backend() {
  if command -v security >/dev/null 2>&1; then
    echo "macos"
  elif command -v secret-tool >/dev/null 2>&1; then
    echo "linux"
  else
    echo "none"
  fi
}

d4a_kc_service() {
  printf 'deploy4artifact:%s' "$1"
}

d4a_kc_set() {
  local profile="$1" field="$2" value="$3" service
  service="$(d4a_kc_service "$profile")"
  case "$(d4a_kc_backend)" in
    macos)
      security add-generic-password -U -a "$field" -s "$service" -w "$value" >/dev/null
      ;;
    linux)
      printf '%s' "$value" \
        | secret-tool store --label="deploy4artifact $profile $field" \
            service "$service" account "$field"
      ;;
    *)
      d4a_die "no OS keychain found (need macOS 'security' or Linux 'secret-tool'); refusing to store '$field' in plaintext"
      ;;
  esac
}

d4a_kc_get() {
  local profile="$1" field="$2" service
  service="$(d4a_kc_service "$profile")"
  case "$(d4a_kc_backend)" in
    macos)
      security find-generic-password -a "$field" -s "$service" -w 2>/dev/null
      ;;
    linux)
      secret-tool lookup service "$service" account "$field" 2>/dev/null
      ;;
    *)
      d4a_die "no OS keychain found (need macOS 'security' or Linux 'secret-tool')"
      ;;
  esac
}

d4a_kc_delete() {
  local profile="$1" field="$2" service
  service="$(d4a_kc_service "$profile")"
  case "$(d4a_kc_backend)" in
    macos)
      security delete-generic-password -a "$field" -s "$service" >/dev/null 2>&1 || true
      ;;
    linux)
      secret-tool clear service "$service" account "$field" >/dev/null 2>&1 || true
      ;;
    *)
      : # nothing to clean up without a keychain backend
      ;;
  esac
}
