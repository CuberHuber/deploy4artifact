# deploy4artifact v1: containerized deploy design

Status: approved (conversational design), pending written-spec review
Date: 2026-09-25
Supersedes: the v0.1.0 MVP shipped in the initial commit (plain `rsync` of raw
artifact files to a path, no containerization, no reverse proxy)

## Context

v0.1.0 fetched a Claude artifact's published files and copied them either to
a local path or to a VPS path over SSH. That's it — no isolation, no public
URL, no way to run more than one deployed artifact on a box without manual
port/path bookkeeping.

The user wants a real (if intentionally small) deploy pipeline: fetch an
artifact, prepare it, run it in an isolated container, and expose it at a
public URL through a managed reverse proxy with TLS — while keeping every
decision-making piece on the device running the plugin. The full original
ask described a much larger system (multi-tier environments, a local index
DB with public/private ACLs, subdomain routing, capability emulation). That
was scoped down deliberately; see "Non-goals" below and the linked backlog
issues for what got deferred and why.

## Goals (v1 scope)

1. Obtain a Claude artifact three ways: an explicit URL, a URL pasted
   earlier in conversation, or picked from the user's own `claude.ai`
   artifact list (via the `Artifact` tool, `action: "list"`).
2. Detect use of Claude's runtime capabilities (`window.claude.*` calls)
   in the fetched files and warn — those calls have no backend once
   self-hosted and will silently no-op.
3. Prepare the artifact for path-prefix hosting by injecting
   `<base href="/d4a/a/<slug>/">` into its entry HTML.
4. Deploy it to a single managed VPS, reached over SSH, running in a
   Docker container with no network egress.
5. Expose it via Traefik at `https://<domain>/d4a/a/<slug>/` with
   automatic TLS (Let's Encrypt, HTTP-01).
6. List, health-check, and remove deployments.
7. All orchestration/decision-making runs on the local device; the VPS
   only executes what it's told (bootstrap, run, remove).

## Non-goals (v1) — tracked as backlog issues

- Multiple/local/home-server environment tiers, per-environment
  user/group/filesystem isolation — [#7](https://github.com/CuberHuber/deploy4artifact/issues/7)
- A real local index DB and public/private access control — [#1](https://github.com/CuberHuber/deploy4artifact/issues/1)
- Subdomain-based routing as an alternative to path-prefix — [#2](https://github.com/CuberHuber/deploy4artifact/issues/2)
- A capability shim/emulation backend (vs. detect-and-warn only) — [#3](https://github.com/CuberHuber/deploy4artifact/issues/3)
- Deployment versioning/rollback/history — [#4](https://github.com/CuberHuber/deploy4artifact/issues/4)
- Per-deployment container resource limits/quotas — [#5](https://github.com/CuberHuber/deploy4artifact/issues/5)
- Registry-based image transport (vs. bind-mount, see Approach B below) — [#6](https://github.com/CuberHuber/deploy4artifact/issues/6)

## Architecture

**Local device ("the brain")** — runs the plugin. Holds the VPS SSH
profile (keychain-backed, existing `vps-profiles` skill, extended with
two new non-secret fields: `domain`, `acme_email`) and a flat local
registry `~/.deploy4artifact/deployments.list` (slug → VPS profile,
deployed-at). All fetching, capability-checking, base-href injection,
and remote-script generation happens here.

**VPS (managed environment)** — runs Docker plus one Traefik container
(bootstrapped once, idempotently, on first deploy to a profile), plus a
filesystem tree `/srv/deploy4artifact/artifacts/<slug>/` holding each
deployed artifact's static files, plus one `nginx:alpine` container per
deployed artifact, bind-mounted read-only to its directory. The VPS
never makes deployment decisions — it only executes generated scripts.

**Docker networking** — one network `d4a-internal`, created with
`--internal` (Docker blocks all outbound internet access from
`--internal` networks; container-to-container traffic within it still
works). Traefik joins `d4a-internal` plus a normal public-facing network
for `:80`/`:443`/ACME. Every deployed artifact container joins *only*
`d4a-internal` — reachable by Traefik, no route to the internet, ever.
Traefik runs with `exposedByDefault=false`, so it only ever routes
containers explicitly labeled `traefik.enable=true` — it can't
accidentally expose something else already running on the box.

## Container strategy: bind-mount, not per-artifact image builds

Two approaches were considered:

- **Build a real per-artifact image** (`docker build` locally, `docker
  save | ssh ... docker load`, `docker run`) — most literally matches
  "build a tiny container," produces an immutable self-contained image,
  but needs Docker on the local device and re-transfers the full image
  (including the unchanging `nginx:alpine` base layer) on every deploy.
- **One generic base image, artifact files bind-mounted at run time**
  (chosen) — `nginx:alpine` is pulled on the VPS once (a public image,
  no transfer needed); every deploy just `rsync`s the small prepared
  artifact files to a directory on the VPS and runs `nginx:alpine`
  bind-mounted to it. No local Docker required, no image build, no
  save/load. "Preparing a tiny container" becomes "assemble a
  directory + generate a run script," which is both simpler and mostly
  reuses the existing v0.1 `deploy-vps.sh` rsync logic.

Chosen: bind-mount. If a future artifact ever needs more than static
serving (e.g. the capability-shim backlog item), that's when
per-artifact custom images earn their cost — this doesn't foreclose it.

## Data flow (per deploy)

1. Resolve and validate the artifact URL (existing
   `check-artifact-url.sh`); if none given, offer "paste a link" vs.
   "pick from my artifacts" (`Artifact` tool, `action: "list"`) as the
   first menu choice.
2. Fetch via the `Artifact` tool (`action: "read"`) → local `out_dir`.
3. **Prepare:**
   - Scan fetched HTML/JS for `window.claude` usage
     (`check-capabilities.sh`). If found, `AskUserQuestion`: proceed
     anyway (those calls will no-op) or abort. Non-fatal, but requires
     an explicit choice — never silently continue past it.
   - Determine the slug: ask the user, default to a sanitized artifact
     id. If the slug already exists in the local registry,
     `AskUserQuestion` to confirm before overwriting — could be an
     intentional redeploy or an accidental clobber of something else.
   - Inject `<base href="/d4a/a/<slug>/">` into the entry HTML's
     `<head>` (`inject-base-href.sh`) — idempotent, errors clearly if
     no `<head>` tag is found rather than corrupting the file.
4. **Bootstrap the VPS, idempotently** (only runs work if missing):
   - Check for Docker. If absent, `AskUserQuestion`: install via the
     distro's package manager, or abort with manual setup
     instructions. Never silently `curl | sh` as root.
   - Check for a running Traefik container (`d4a-traefik`). If absent,
     create `d4a-internal`, start Traefik with ACME HTTP-01 using the
     profile's `acme_email`, `exposedByDefault=false`, joined to both
     `d4a-internal` and the public network.
5. **Deploy:**
   - `mkdir -p /srv/deploy4artifact/artifacts/<slug>` and `rsync` the
     prepared files there (same validated pattern as today's
     `deploy-vps.sh`; target path is now computed, not user-supplied).
   - Generate a small deploy script locally (stop/remove any prior
     `d4a-<slug>` container, then `docker run` the new one:
     bind-mounted read-only, `--network d4a-internal` only,
     `--health-cmd 'wget -q --spider http://localhost/ || exit 1'`,
     `--restart unless-stopped`, labeled `d4a.managed=true` plus the
     Traefik routing/stripprefix/TLS labels). `rsync` this script
     alongside the artifact files, then `ssh` executes it. Generating
     and shipping a script — rather than building one long, quoted SSH
     one-liner with Traefik labels embedded — avoids
     injection-prone, hard-to-audit remote command construction.
6. Report `https://<domain>/d4a/a/<slug>/` back to the user.
7. Update the local registry.

## Deployments skill: list / health / remove

New skill, `deployments`, alongside the extended `deploy-artifact` and
`vps-profiles`:

- **List:** read the local registry; for each entry, SSH to the VPS and
  query containers by the `d4a.managed=true` label (never touches
  containers this plugin didn't create).
- **Health check:** two layers — Docker's own health status
  (`docker inspect`, driven by the `--health-cmd` set at deploy time)
  for "is the container alive," plus a real HTTPS request through
  Traefik to the public URL for "does the full path actually work"
  (proxy routing and TLS included, not just container liveness).
  Degrades gracefully to "unreachable" on SSH/network failure rather
  than crashing.
- **Remove:** stop and remove the container (Traefik's routing
  disappears automatically — it's driven off the running, labeled
  container, nothing to separately unconfigure), delete the VPS-side
  artifact directory, drop the local registry entry.

## Plugin file structure

```
skills/
  deploy-artifact/       existing, extended: capability-check, slug
                          selection/collision handling, base-href
                          injection, calls new bootstrap+deploy mechanics
  vps-profiles/           existing, extended: domain + acme_email fields
  deployments/            new: list, health, remove
scripts/
  lib/
    common.sh, validate.sh, keychain.sh, profiles.sh   (unchanged)
  check-artifact-url.sh   (existing, unchanged)
  deploy-local.sh         (existing; local-target semantics unchanged)
  deploy-vps.sh           (existing rsync pattern, reused by the new
                            per-deploy artifact-directory sync)
  vps-profile.sh          (existing, extended: domain/acme_email)
  check-capabilities.sh   (new)
  inject-base-href.sh     (new)
  bootstrap-vps.sh        (new: idempotent Docker/Traefik/network setup)
  generate-run-script.sh  (new: pure function — builds the per-deploy
                            docker-run script text; no I/O)
  list-deployments.sh     (new)
  health-check.sh         (new)
  remove-deployment.sh    (new)
```

All `$CLAUDE_PLUGIN_ROOT`-relative references in SKILL.md files, all
scripts self-locate via `BASH_SOURCE`, consistent with the existing
v0.1 pattern and `plugin-dev:plugin-structure` conventions.

## Security model

- **No network egress from any deployed artifact container, ever** —
  `--internal` Docker network, not a runtime toggle.
- **Traefik only routes what's explicitly labeled** — `exposedByDefault
  =false` prevents accidental exposure of anything else on the VPS.
- **No silent privileged installs** — Docker install requires explicit
  user confirmation, never an unattended `curl | sh` as root.
- **No secrets or injection-prone strings built into SSH one-liners** —
  remote actions are generated as script files and shipped, not
  interpolated into a single quoted command string.
- **Explicit checkpoints, not silent continuation** — capability-usage
  warnings and slug-collision overwrites both require an affirmative
  `AskUserQuestion` answer before proceeding.
- **Existing keychain-only secret handling carries over unchanged**
  (see `skills/deploy-artifact/references/security-model.md`).

## Error handling

Every remote/build step fails loud and stops before the next one — no
partial deploys left half-configured. Idempotent bootstrap and
container replacement make a failed/retried deploy safe to re-run.
Read-only operations (list, health-check) degrade to "unreachable"
rather than crashing on SSH/network failure.

## Testing strategy

- `bats` coverage for all new pure logic: `inject-base-href.sh`
  (idempotency, missing-`<head>` error, tag-casing variations),
  `check-capabilities.sh` (true/false positive detection), slug
  validation (same pattern as the existing profile-name validator).
- `generate-run-script.sh` is a pure "build the script text" function,
  unit-tested directly (assert expected bind-mount/network/labels for
  given inputs) — separated from the "SSH and execute it" I/O wrapper
  so the logic that matters is testable without a real VPS.
- A Docker-based integration test, runnable in CI (GitHub's
  `ubuntu-latest` ships Docker): create a real `d4a-internal` network,
  run a throwaway container on it, assert outbound internet access
  fails from inside while container-to-container reachability on that
  network works. This is the core security property of the whole
  design — it gets verified, not just claimed.
- SSH-dependent end-to-end flows (real rsync-to-VPS, real bootstrap)
  remain manually/integration tested against a real VPS — the same gap
  already flagged by the plugin-validator for the existing
  `deploy-vps.sh`, now explicitly acknowledged rather than silently
  inherited.

## Known residual limitations

- Path-prefix routing plus `<base href>` injection fixes all
  *declared* relative asset references (Claude artifacts publish file
  references as relative paths with no leading slash — confirmed from
  the `Artifact` tool's own spec). It does **not** fix an artifact's
  own JavaScript making a runtime `fetch()`/`XHR` call with a
  hardcoded leading-slash path. Rare in practice; tracked via the
  subdomain-routing backlog item (#2) as the eventual complete fix.
- Single VPS profile only in v1 (#7 tracks multi-environment support).
