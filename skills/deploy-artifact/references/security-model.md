# Security model: how deploy4artifact protects secrets

deploy4artifact handles two classes of sensitive input: VPS credentials
(host, user, SSH key or password) and third-party artifact content fetched
from `claude.ai`. Both are treated as adversarial by default.

## OWASP LLM Top 10 mapping

| Risk | Guardrail | Where enforced |
|---|---|---|
| LLM01 Prompt Injection | Artifact content is read once via the `Artifact` tool and never re-interpreted as instructions; the skill never executes fetched HTML/JS/markdown. | `deploy-artifact` SKILL.md, Step 2 |
| LLM02 Insecure Output Handling | Deploy scripts never `eval` input; all paths and hostnames pass through `scripts/lib/validate.sh` before use in a shell command. | `validate.sh` |
| LLM06 Sensitive Information Disclosure | Secrets are never constructed into a Bash tool call, never printed to stdout, never written to a plaintext config file. Only a profile *name* lives outside the keychain. | `scripts/lib/keychain.sh`, `scripts/vps-profile.sh` |
| LLM08 Excessive Agency | The skill asks before overwriting a destination and before removing a profile; it never auto-selects a deploy target. | `deploy-artifact` SKILL.md, Step 3 |
| Supply chain / SSRF-adjacent | Artifact URLs are restricted to `https://claude.ai/(code/)?artifact/...`; VPS hosts are validated as a hostname or IPv4 literal before use. | `validate.sh` |

## Why secrets never pass through the conversation

Claude Code's Bash tool captures the full command text of everything it
runs, which becomes part of the visible conversation. Any script invoked
*by the assistant* that takes a secret as a CLI argument, or that the
assistant pipes a secret into via stdin, leaks that secret into the
transcript. `vps-profile.sh add` is designed around this constraint:

- **Key auth** takes a file *path*, not key content — the script reads the
  file server-side, so only the path (not the key) ever appears in a tool
  call.
- **Password auth** requires a real interactive terminal (`[[ -t 0 ]]`).
  Claude Code's Bash tool never provides one, so the script detects this
  and refuses, telling the user to run the command themselves in their own
  terminal instead. This is intentional fail-closed behavior — do not
  attempt to script around it by feeding the password through stdin or an
  environment variable from the assistant side.

## Why the keychain, not a config file

Storing `vps_ip`, `vps_user`, the SSH key, and the password in the OS
keychain (rather than a dotfile) means:

- Values are encrypted at rest by the OS, gated behind the user's login
  session rather than filesystem permissions alone.
- A stray `git add .` or backup tool cannot accidentally include them —
  there is no file to include.
- Removing a profile (`vps-profile.sh remove`) deletes the keychain
  entries directly; nothing lingers in a shell history file or a
  `~/.deploy4artifact/*.conf`.

Only the profile *name* — an arbitrary label the user chose, never itself
a credential — lives in `~/.deploy4artifact/profiles.list` (mode `600`),
so profiles can be listed without touching the keychain for every read.

## Transport security

Deploys run over `rsync -e ssh`. Host keys are pinned per-invocation to
`~/.deploy4artifact/known_hosts` (mode `600`) with
`StrictHostKeyChecking=accept-new` — trust-on-first-use, never
`StrictHostKeyChecking=no`. A changed host key on a known profile causes
`ssh` to refuse the connection rather than silently proceeding.

Temporary SSH key material written to disk during a `key`-auth deploy is
created with `mktemp` (mode `600`, private tmpdir) and removed via a
`trap ... EXIT`, using `shred -u` when available, on both success and
failure paths.
