#!/usr/bin/env bats
# SPDX-FileCopyrightText: Copyright (c) 2026 CuberHuber
# SPDX-License-Identifier: MIT

load '../helpers/stubs'

setup() {
  d4a_stubs_setup
  d4a_stubs_profile demo
  LIBS="source '$SCRIPTS/lib/common.sh'; source '$SCRIPTS/lib/validate.sh'; source '$SCRIPTS/lib/keychain.sh'; source '$SCRIPTS/lib/remote.sh'"
}

teardown() {
  d4a_stubs_teardown
}

@test "d4a_remote_run pipes the script to bash -s on the target" {
  printf 'hello-back' > "$STUB_LOG/ssh.reply.1"
  run bash -c "$LIBS; trap d4a_remote_cleanup EXIT; d4a_remote_open demo; d4a_remote_run 'echo hi'"
  [ "$status" -eq 0 ]
  [ "$output" = "hello-back" ]
  grep -qF "deploy@203.0.113.5 bash -s" "$STUB_LOG/ssh.args"
  [ "$(cat "$STUB_LOG/ssh.stdin.1")" = "echo hi" ]
}

@test "d4a_remote_open hands ssh the multi-line key intact, not hex" {
  _d4a_stub ssh <<'EOF'
#!/usr/bin/env bash
while [ $# -gt 0 ]; do
  if [ "$1" = -i ]; then cp "$2" "$STUB_LOG/key.seen"; fi
  shift
done
EOF
  run bash -c "$LIBS; trap d4a_remote_cleanup EXIT; d4a_remote_open demo; d4a_remote_run 'true'"
  [ "$status" -eq 0 ]
  [ "$(cat "$STUB_LOG/key.seen")" = "$(printf 'FAKE-KEY-HEADER\nFAKE-KEY-BODY\nFAKE-KEY-FOOTER')" ]
}

@test "d4a_kc_get keeps a single-line value that looks like hex verbatim" {
  printf 'deadbeef' > "$KC_DIR/deploy4artifact:demo/vps_pass"
  run bash -c "$LIBS; d4a_kc_get demo vps_pass"
  [ "$status" -eq 0 ]
  [ "$output" = "deadbeef" ]
}

@test "d4a_kc_get fails for a missing field" {
  run bash -c "$LIBS; d4a_kc_get demo no_such_field"
  [ "$status" -ne 0 ]
}

@test "d4a_remote_run returns the ssh exit status" {
  printf '255' > "$STUB_LOG/ssh.exit.1"
  run bash -c "$LIBS; trap d4a_remote_cleanup EXIT; d4a_remote_open demo; d4a_remote_run 'true'"
  [ "$status" -eq 255 ]
}

@test "d4a_kv extracts one value from key=value lines" {
  run bash -c "$LIBS; d4a_kv traefik \$'docker=ok\ntraefik=running'"
  [ "$output" = "running" ]
}
