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
