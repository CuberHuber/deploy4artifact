---
name: deployments
description: This skill should be used when the user asks to "list my deployments", "what artifacts are deployed", "is my artifact up", "check deployment health", "remove a deployed artifact", "take down <slug>", or otherwise wants to inspect or delete artifacts that deploy4artifact deployed to a VPS.
argument-hint: "[list|health|remove] [slug]"
allowed-tools: AskUserQuestion, Bash, Read
version: 0.2.0
---

# Manage deployed artifacts

Inspect and remove artifacts deployed by the `deploy-artifact` skill. The
local registry at `~/.deploy4artifact/deployments.list` records which
profile each slug lives on; every command then asks that VPS over SSH. It
only ever touches containers labeled `d4a.managed=true`.

## List

```sh
bash "$CLAUDE_PLUGIN_ROOT/scripts/deployments.sh" list
```

Prints one row per deployment: slug, profile, deploy time, and status.
Status is Docker's container status (for example `Up 2 hours (healthy)`),
`missing` if the VPS has no such container, or `unreachable` if SSH failed.

## Health check

```sh
bash "$CLAUDE_PLUGIN_ROOT/scripts/deployments.sh" health <slug>
```

Prints `container=` (Docker state and health), `https=` (the status code of
a real request through the proxy, `000` if it could not connect), `url=`,
and `overall=ok|degraded|unreachable`. For `degraded`, explain which layer
failed: a healthy container with a failing HTTPS request points at the
proxy, TLS, or DNS rather than the artifact.

## Remove

Confirm with `AskUserQuestion` first, naming the slug and its URL; removal
deletes the container and its files on the VPS and cannot be undone. Then:

```sh
bash "$CLAUDE_PLUGIN_ROOT/scripts/deployments.sh" remove <slug>
```

The registry entry is dropped only after the VPS side succeeds. The script
refuses to remove a container that deploy4artifact did not create.
