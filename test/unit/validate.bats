#!/usr/bin/env bats
# SPDX-FileCopyrightText: Copyright (c) 2026 CuberHuber
# SPDX-License-Identifier: MIT

setup() {
  DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../scripts" && pwd)"
  # shellcheck source=/dev/null
  source "$DIR/lib/common.sh"
  # shellcheck source=/dev/null
  source "$DIR/lib/validate.sh"
}

@test "accepts a valid profile name" {
  run d4a_validate_profile_name "prod-server_1"
  [ "$status" -eq 0 ]
}

@test "rejects a profile name with spaces" {
  run d4a_validate_profile_name "prod server"
  [ "$status" -ne 0 ]
}

@test "accepts a claude.ai artifact URL" {
  run d4a_validate_artifact_url "https://claude.ai/artifact/abc123"
  [ "$status" -eq 0 ]
}

@test "accepts a claude.ai code artifact URL" {
  run d4a_validate_artifact_url "https://claude.ai/code/artifact/abc123"
  [ "$status" -eq 0 ]
}

@test "rejects a non-claude.ai URL" {
  run d4a_validate_artifact_url "https://evil.example/artifact/abc123"
  [ "$status" -ne 0 ]
}

@test "accepts a valid IPv4 host" {
  run d4a_validate_host "203.0.113.5"
  [ "$status" -eq 0 ]
}

@test "rejects an out-of-range IPv4 octet" {
  run d4a_validate_host "999.0.113.5"
  [ "$status" -ne 0 ]
}

@test "accepts a valid hostname" {
  run d4a_validate_host "vps.example.com"
  [ "$status" -eq 0 ]
}

@test "accepts a valid port" {
  run d4a_validate_port "22"
  [ "$status" -eq 0 ]
}

@test "accepts a port with a leading zero without octal misparsing" {
  run d4a_validate_port "022"
  [ "$status" -eq 0 ]
}

@test "rejects an out-of-range port" {
  run d4a_validate_port "70000"
  [ "$status" -ne 0 ]
}

@test "accepts an absolute local destination" {
  run d4a_validate_local_dest "/srv/site"
  [ "$status" -eq 0 ]
}

@test "rejects a relative local destination" {
  run d4a_validate_local_dest "srv/site"
  [ "$status" -ne 0 ]
}

@test "rejects a local destination with path traversal" {
  run d4a_validate_local_dest "/srv/../etc/passwd"
  [ "$status" -ne 0 ]
}

@test "rejects a system local destination" {
  run d4a_validate_local_dest "/etc"
  [ "$status" -ne 0 ]
}

@test "rejects a system remote path" {
  run d4a_validate_remote_path "/bin"
  [ "$status" -ne 0 ]
}

@test "accepts a valid slug" {
  run d4a_validate_slug "my-artifact-2"
  [ "$status" -eq 0 ]
}

@test "rejects slugs with uppercase, underscores, or edge dashes" {
  run d4a_validate_slug "My"
  [ "$status" -ne 0 ]
  run d4a_validate_slug "a_b"
  [ "$status" -ne 0 ]
  run d4a_validate_slug "-a"
  [ "$status" -ne 0 ]
  run d4a_validate_slug "a-"
  [ "$status" -ne 0 ]
}

@test "rejects a 64-character slug" {
  run d4a_validate_slug "$(printf 'a%.0s' {1..64})"
  [ "$status" -ne 0 ]
}

@test "derives a slug from an artifact id" {
  run d4a_slug_from_id "Abc_DEF--123"
  [ "$status" -eq 0 ]
  [ "$output" = "abc-def-123" ]
}

@test "caps a derived slug at 63 characters without a trailing dash" {
  run d4a_slug_from_id "$(printf 'a%.0s' {1..62})_zzz"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'a%.0s' {1..62})" ]
}

@test "a slug derived from a non-ASCII id is valid or refused, in any locale" {
  local loc
  for loc in C en_US.UTF-8 C.UTF-8; do
    run env LC_ALL="$loc" bash -c 'source "$1/lib/common.sh"; source "$1/lib/validate.sh"; d4a_slug_from_id "Café-ÜBER-ı-Ⅻ"' _ "$DIR"
    echo "locale=$loc status=$status output=$output"
    if [ "$status" -eq 0 ]; then
      [[ "$output" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]]
    else
      [[ "$output" == *"invalid slug"* || "$output" == *"cannot derive a slug"* ]]
    fi
  done
}

@test "refuses a derived slug that a locale-dependent sed left non-ASCII" {
  sed() { cat; }
  run d4a_slug_from_id "café"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid slug"* ]]
}

@test "refuses to derive a slug from punctuation only" {
  run d4a_slug_from_id "___"
  [ "$status" -ne 0 ]
}

@test "accepts a lowercase domain" {
  run d4a_validate_domain "d4a.example.com"
  [ "$status" -eq 0 ]
}

@test "rejects an IP address, a bare hostname, and uppercase as a domain" {
  run d4a_validate_domain "203.0.113.5"
  [ "$status" -ne 0 ]
  run d4a_validate_domain "localhost"
  [ "$status" -ne 0 ]
  run d4a_validate_domain "Example.com"
  [ "$status" -ne 0 ]
}

@test "accepts a plausible email and rejects a non-email" {
  run d4a_validate_email "ops+certs@example.com"
  [ "$status" -eq 0 ]
  run d4a_validate_email "not-an-email"
  [ "$status" -ne 0 ]
}
