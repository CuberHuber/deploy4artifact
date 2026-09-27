# SPDX-FileCopyrightText: Copyright (c) 2026 CuberHuber
# SPDX-License-Identifier: MIT
#
# Test doubles for scripts that talk to Docker, the OS keychain, or a VPS.
# In a .bats file: load '../helpers/stubs', call d4a_stubs_setup in setup()
# and d4a_stubs_teardown in teardown(). Each stub appends its argv as one
# line to $STUB_LOG/<name>.args.
#
# docker: STUB_DOCKER_INFO_EXIT, STUB_DOCKER_INSPECT(_EXIT), STUB_DOCKER_PS;
# a d4a.managed label query answers STUB_DOCKER_MANAGED (falling back to
# STUB_DOCKER_INSPECT, then "true"); "network inspect" exits
# STUB_DOCKER_NETWORK_EXIT and prints STUB_DOCKER_NETWORK_INTERNAL (default
# "true"). sudo exits STUB_SUDO_EXIT (default 0) without running anything.

d4a_stubs_setup() {
  SCRIPTS="$(cd "$BATS_TEST_DIRNAME/../../scripts" && pwd)"
  STUB_BIN="$(mktemp -d)"
  STUB_LOG="$(mktemp -d)"
  KC_DIR="$(mktemp -d)"
  D4A_HOME="$(mktemp -d)"
  TMPDIR="$(mktemp -d)"
  export SCRIPTS STUB_BIN STUB_LOG KC_DIR D4A_HOME TMPDIR
  export PATH="$STUB_BIN:$PATH"

  _d4a_stub docker <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_LOG/docker.args"
case "$1" in
  info) exit "${STUB_DOCKER_INFO_EXIT:-0}" ;;
  inspect)
    [ "${STUB_DOCKER_INSPECT_EXIT:-0}" -eq 0 ] || exit "$STUB_DOCKER_INSPECT_EXIT"
    case "$*" in
      *d4a.managed*)
        if [ -n "${STUB_DOCKER_MANAGED+x}" ]; then printf '%s\n' "$STUB_DOCKER_MANAGED"
        elif [ -n "${STUB_DOCKER_INSPECT+x}" ]; then printf '%s\n' "$STUB_DOCKER_INSPECT"
        else printf 'true\n'
        fi
        ;;
      *) printf '%s\n' "${STUB_DOCKER_INSPECT-healthy}" ;;
    esac
    ;;
  network)
    if [ "$2" = inspect ]; then
      [ "${STUB_DOCKER_NETWORK_EXIT:-0}" -eq 0 ] || exit "$STUB_DOCKER_NETWORK_EXIT"
      printf '%s\n' "${STUB_DOCKER_NETWORK_INTERNAL-true}"
    fi
    ;;
  ps) printf '%s' "${STUB_DOCKER_PS:-}" ;;
esac
exit 0
EOF

  _d4a_stub sudo <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_LOG/sudo.args"
exit "${STUB_SUDO_EXIT:-0}"
EOF

  _d4a_stub security <<'EOF'
#!/usr/bin/env bash
cmd="$1"; shift
acct=""; svc=""; val=""; want_w=0; want_g=0
while [ $# -gt 0 ]; do
  case "$1" in
    -a) acct="$2"; shift 2 ;;
    -s) svc="$2"; shift 2 ;;
    -w) want_w=1; if [ $# -ge 2 ]; then val="$2"; shift 2; else shift; fi ;;
    -g) want_g=1; shift ;;
    *) shift ;;
  esac
done
f="$KC_DIR/$svc/$acct"
case "$cmd" in
  add-generic-password) mkdir -p "$KC_DIR/$svc"; printf '%s' "$val" > "$f" ;;
  find-generic-password)
    [ -f "$f" ] || exit 44
    # Like the real tool: a value holding non-printable bytes (the newlines
    # of a multi-line key) comes back hex-encoded, and -g flags it with 0x.
    hex=""
    if [ "$(LC_ALL=C tr -d '[:print:]' < "$f" | wc -c)" -gt 0 ]; then
      hex="$(od -An -tx1 -v "$f" | tr -d ' \n')"
    fi
    if [ "$want_g" -eq 1 ]; then
      if [ -n "$hex" ]; then
        printf 'password: 0x%s  "(elided)"\n' "$(printf '%s' "$hex" | tr '[:lower:]' '[:upper:]')" >&2
      else
        printf 'password: "%s"\n' "$(cat "$f")" >&2
      fi
    fi
    if [ "$want_w" -eq 1 ]; then
      if [ -n "$hex" ]; then printf '%s\n' "$hex"; else cat "$f"; echo; fi
    fi
    ;;
  delete-generic-password) rm -f "$f" ;;
esac
EOF

  _d4a_stub ssh <<'EOF'
#!/usr/bin/env bash
n=$(( $(cat "$STUB_LOG/ssh.count" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$STUB_LOG/ssh.count"
printf '%s\n' "$*" >> "$STUB_LOG/ssh.args"
cat > "$STUB_LOG/ssh.stdin.$n"
if [ -f "$STUB_LOG/ssh.reply.$n" ]; then cat "$STUB_LOG/ssh.reply.$n"; fi
exit "$(cat "$STUB_LOG/ssh.exit.$n" 2>/dev/null || echo 0)"
EOF

  _d4a_stub rsync <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_LOG/rsync.args"
exit 0
EOF

  _d4a_stub curl <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_LOG/curl.args"
printf '%s' "${STUB_CURL_CODE:-200}"
EOF
}

d4a_stubs_teardown() {
  rm -rf "$STUB_BIN" "$STUB_LOG" "$KC_DIR" "$D4A_HOME" "$TMPDIR"
}

d4a_stubs_profile() {
  local name="$1" svc="$KC_DIR/deploy4artifact:$1"
  mkdir -p "$svc" "$D4A_HOME"
  printf '203.0.113.5' > "$svc/vps_ip"
  printf 'deploy' > "$svc/vps_user"
  printf '22' > "$svc/vps_port"
  printf 'key' > "$svc/auth_method"
  printf 'FAKE-KEY-HEADER\nFAKE-KEY-BODY\nFAKE-KEY-FOOTER' > "$svc/vps_ssh_key"
  if [ -n "${2:-}" ]; then printf '%s' "$2" > "$svc/site_domain"; fi
  if [ -n "${3:-}" ]; then printf '%s' "$3" > "$svc/acme_email"; fi
  printf '%s\n' "$name" >> "$D4A_HOME/profiles.list"
}

_d4a_stub() {
  cat > "$STUB_BIN/$1"
  chmod +x "$STUB_BIN/$1"
}
