---
name: vps-profiles
description: This skill should be used when the user asks to "add a VPS profile", "save my VPS credentials", "configure a deploy target", "list my VPS profiles", "remove a VPS profile", "set up SSH deploy credentials", or otherwise wants to manage the saved servers deploy4artifact can deploy to. Manages named VPS connection profiles (host, user, port, auth method) with all credentials stored in the OS keychain, never on disk or in conversation.
argument-hint: "[list|show|add|remove] [profile-name]"
allowed-tools: AskUserQuestion, Bash, Read
version: 0.1.0
---

# Manage VPS deploy profiles

Create, inspect, and remove named VPS profiles that `deploy-artifact` deploys
to. Every profile's host, user, port, auth method, and secret (SSH private
key or password) lives only in the OS keychain (macOS Keychain via
`security`, or Linux Secret Service via `secret-tool`); only the profile
*name* is recorded outside the keychain, in
`~/.deploy4artifact/profiles.list` (mode 600, names only — no connection
details).

## List or inspect profiles

```sh
bash "$CLAUDE_PLUGIN_ROOT/scripts/vps-profile.sh" list
bash "$CLAUDE_PLUGIN_ROOT/scripts/vps-profile.sh" show <name>
```

`show` prints host, user, port, and auth method — never the secret itself.

## Add a profile

Gather the non-secret fields first with `AskUserQuestion`: profile name
(letters, digits, `-`, `_`, max 64 chars), host or IP, SSH user, port
(default 22), and auth method (`key` recommended, or `password`).

**Key auth** — never ask the user to paste key material into this
conversation. Ask for the *path* to an existing private key file (e.g.
`~/.ssh/id_ed25519`) and pass only that path; the script reads the file
itself, so the key content never appears in a tool call or transcript:

```sh
bash "$CLAUDE_PLUGIN_ROOT/scripts/vps-profile.sh" add <name> <host> <user> <port> key --key-file <path>
```

**Password auth** — this tool has no channel to accept sensitive input
without it passing through the conversation transcript, so never run the
password-add command directly. Instead tell the user to open their own
terminal and run it themselves:

```sh
bash "$CLAUDE_PLUGIN_ROOT/scripts/vps-profile.sh" add <name> <host> <user> <port> password
```

Run without a terminal attached (as this skill would invoke it), the script
refuses and prints this same instruction rather than silently falling back
to an insecure input path — do not try to work around that refusal.
Recommend key auth over password auth whenever the user is open to it;
password auth also requires `sshpass` to be installed for the later deploy
step.

## Remove a profile

```sh
bash "$CLAUDE_PLUGIN_ROOT/scripts/vps-profile.sh" remove <name>
```

Deletes every keychain entry for the profile and drops it from the local
name registry. Confirm the profile name with the user before running this
— it is not reversible.

## Additional resources

- `../deploy-artifact/references/security-model.md` — shared with
  `deploy-artifact`; explains why secrets never touch argv, stdin from
  Claude, or disk in plaintext.
- `scripts/vps-profile.sh` — the script referenced above.
