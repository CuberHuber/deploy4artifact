#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2026 CuberHuber
# SPDX-License-Identifier: MIT
#
# List, health-check, and remove artifacts recorded by deploy.sh, and turn
# free text into a slug. Reads the local registry and talks to each VPS
# over SSH; read-only commands degrade to "unreachable" instead of failing.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib/common.sh
source "$DIR/lib/common.sh"
# shellcheck source=./lib/validate.sh
source "$DIR/lib/validate.sh"
# shellcheck source=./lib/keychain.sh
source "$DIR/lib/keychain.sh"
# shellcheck source=./lib/remote.sh
source "$DIR/lib/remote.sh"
# shellcheck source=./lib/remote-scripts.sh
source "$DIR/lib/remote-scripts.sh"
# shellcheck source=./lib/registry.sh
source "$DIR/lib/registry.sh"

trap d4a_remote_cleanup EXIT

usage() {
  cat <<'EOF'
Usage:
  deployments.sh list
  deployments.sh health <slug>
  deployments.sh remove <slug>
  deployments.sh suggest-slug <text>

list          SLUG PROFILE DEPLOYED_AT STATUS per recorded deployment
health        container state plus a real HTTPS request through the proxy
remove        delete the container and its files on the VPS, then forget the slug
suggest-slug  turn <text> into a valid slug and say whether it is taken
EOF
}

# Callers use this in an `if`, where errexit is off, so every failure inside
# must end in an explicit exit (d4a_die) or be the subshell's last status.
remote_capture() {
  (
    trap d4a_remote_cleanup EXIT
    d4a_remote_open "$1"
    d4a_remote_run "$2"
  )
}

profile_of() {
  local line
  line="$(d4a_reg_get "$1")" || d4a_die "no deployment named '$1' (see: deployments.sh list)"
  printf '%s' "$line" | cut -f2
}

cmd_list() {
  local reg script profiles p out statuses="" slug ts st
  reg="$(d4a_reg_path)"
  if [[ ! -s "$reg" ]]; then
    d4a_log "no deployments recorded"
    return 0
  fi
  script="$(d4a_gen_list_script)"
  profiles="$(cut -f2 "$reg" | sort -u)"
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    if out="$(remote_capture "$p" "$script")"; then
      statuses+="$(printf '%s\n' "$out" | awk -F'\t' -v p="$p" 'NF >= 2 { print p "\t" $1 "\t" $2 }')"$'\n'
    else
      statuses+="$(printf '%s\t*\tunreachable' "$p")"$'\n'
    fi
  done <<< "$profiles"
  printf 'SLUG\tPROFILE\tDEPLOYED_AT\tSTATUS\n'
  while IFS=$'\t' read -r slug p ts; do
    [[ -n "$slug" ]] || continue
    st="$(printf '%s' "$statuses" \
      | awk -F'\t' -v p="$p" -v s="$slug" '$1 == p && ($2 == s || $2 == "*") { print $3; exit }')"
    printf '%s\t%s\t%s\t%s\n' "$slug" "$p" "$ts" "${st:-missing}"
  done < "$reg"
}

cmd_health() {
  local slug="${1:-}" profile domain script container code overall
  [[ -n "$slug" ]] || { usage; exit 2; }
  d4a_validate_slug "$slug"
  profile="$(profile_of "$slug")"
  domain="$(d4a_kc_get "$profile" site_domain)" \
    || d4a_die "no site_domain for profile '$profile'"
  d4a_validate_domain "$domain"
  script="$(d4a_gen_health_script "$slug")"
  if ! container="$(remote_capture "$profile" "$script")"; then
    container="unreachable"
  fi
  d4a_require_cmd curl
  code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 "https://$domain/d4a/a/$slug/" 2>/dev/null)" \
    || code="000"
  if [[ "$container" == "running healthy" && "$code" == 200 ]]; then
    overall=ok
  elif [[ "$container" == unreachable && "$code" == 000 ]]; then
    overall=unreachable
  else
    overall=degraded
  fi
  printf 'container=%s\nhttps=%s\nurl=https://%s/d4a/a/%s/\noverall=%s\n' \
    "$container" "$code" "$domain" "$slug" "$overall"
}

cmd_remove() {
  local slug="${1:-}" profile script
  [[ -n "$slug" ]] || { usage; exit 2; }
  d4a_validate_slug "$slug"
  profile="$(profile_of "$slug")"
  script="$(d4a_gen_remove_script "$slug")"
  d4a_remote_open "$profile"
  d4a_remote_run "$script" >&2
  d4a_reg_remove "$slug"
  d4a_log "removed '$slug' from profile '$profile'"
}

cmd_suggest_slug() {
  local text="${1:-}" slug
  [[ -n "$text" ]] || { usage; exit 2; }
  slug="$(d4a_slug_from_id "$text")"
  printf 'slug=%s\n' "$slug"
  if d4a_reg_exists "$slug"; then
    printf 'taken=yes\n'
  else
    printf 'taken=no\n'
  fi
}

main() {
  local sub="${1:-}"
  [[ -n "$sub" ]] || { usage; exit 2; }
  shift
  case "$sub" in
    list) cmd_list "$@" ;;
    health) cmd_health "$@" ;;
    remove) cmd_remove "$@" ;;
    suggest-slug) cmd_suggest_slug "$@" ;;
    *) usage; exit 2 ;;
  esac
}

main "$@"
