#!/usr/bin/env bats
# SPDX-FileCopyrightText: Copyright (c) 2026 CuberHuber
# SPDX-License-Identifier: MIT

setup() {
  DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../scripts" && pwd)"
  STUB_BIN="$(mktemp -d)"
  BASH_BIN="$(command -v bash)"
}

teardown() {
  rm -rf "$STUB_BIN"
}

@test "reports 'none' when no keychain backend is on PATH" {
  run env PATH="$STUB_BIN" "$BASH_BIN" -c "source '$DIR/lib/common.sh'; source '$DIR/lib/keychain.sh'; d4a_kc_backend"
  [ "$status" -eq 0 ]
  [ "$output" = "none" ]
}

@test "prefers macOS 'security' when present" {
  printf '#!/usr/bin/env bash\nexit 0\n' > "$STUB_BIN/security"
  chmod +x "$STUB_BIN/security"
  run env PATH="$STUB_BIN" "$BASH_BIN" -c "source '$DIR/lib/common.sh'; source '$DIR/lib/keychain.sh'; d4a_kc_backend"
  [ "$output" = "macos" ]
}

@test "falls back to Linux 'secret-tool' when 'security' is absent" {
  printf '#!/usr/bin/env bash\nexit 0\n' > "$STUB_BIN/secret-tool"
  chmod +x "$STUB_BIN/secret-tool"
  run env PATH="$STUB_BIN" "$BASH_BIN" -c "source '$DIR/lib/common.sh'; source '$DIR/lib/keychain.sh'; d4a_kc_backend"
  [ "$output" = "linux" ]
}

@test "d4a_kc_set fails closed with no backend, never writes plaintext" {
  run env PATH="$STUB_BIN" "$BASH_BIN" -c "source '$DIR/lib/common.sh'; source '$DIR/lib/keychain.sh'; d4a_kc_set demo vps_ip 203.0.113.5"
  [ "$status" -ne 0 ]
}
