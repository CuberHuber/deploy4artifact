# deploy4artifact

[![ci](https://github.com/CuberHuber/deploy4artifact/actions/workflows/ci.yml/badge.svg)](https://github.com/CuberHuber/deploy4artifact/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](https://github.com/CuberHuber/deploy4artifact/blob/main/LICENSE.txt)
[![REUSE status](https://api.reuse.software/badge/github.com/CuberHuber/deploy4artifact)](https://api.reuse.software/info/github.com/CuberHuber/deploy4artifact)
[![Hits-of-Code](https://hitsofcode.com/github/CuberHuber/deploy4artifact)](https://hitsofcode.com/view/github/CuberHuber/deploy4artifact)

A [Claude Code](https://claude.com/claude-code) plugin that deploys a
published Claude artifact — from chat, from pasted text, or from your
artifact list — to a local path or a remote VPS over SSH, with every
credential kept in the OS keychain.

## What it does

deploy4artifact does exactly one thing: it takes a `claude.ai` artifact URL
and puts its files somewhere you control.

- **Fetch** — reads the artifact's published files with Claude Code's
  native `Artifact` tool; the content is always treated as untrusted data,
  never executed or followed as instructions.
- **Choose a destination** — an interactive menu (via Claude Code's
  `AskUserQuestion`) offers a local directory or a saved VPS profile.
- **Deploy** — `rsync` over `ssh` to a VPS, or a validated local copy;
  either way, destination paths are checked against traversal and system
  directory footguns before anything runs.
- **Keep secrets out of the way** — VPS host, user, port, and the SSH key
  or password all live in the OS keychain (macOS Keychain or the Linux
  Secret Service via `secret-tool`). Nothing sensitive is ever written to a
  config file, and secret material never appears in a command Claude
  constructs. See
  [the security model](skills/deploy-artifact/references/security-model.md)
  for the full threat model and its OWASP LLM Top 10 mapping.

## Install

Clone this repo and point Claude Code at it:

```sh
git clone https://github.com/CuberHuber/deploy4artifact.git
claude --plugin-dir /path/to/deploy4artifact
```

Or add it as a plugin marketplace entry pointing at this repository, per
Claude Code's
[plugin documentation](https://docs.claude.com/en/docs/claude-code/plugins).

## Usage

Set up a deploy target once:

```text
/deploy4artifact:vps-profiles add
```

Then deploy an artifact by URL, or just paste one in chat and ask to
deploy it:

```text
/deploy4artifact:deploy-artifact https://claude.ai/artifact/<id>
```

Claude walks through fetching the artifact, choosing a destination, and
running the deploy — see `skills/deploy-artifact/SKILL.md` and
`skills/vps-profiles/SKILL.md` for the exact flow.

## How to Contribute

Fork the repo and send a pull request. Every change must build without any
warnings — the same commands CI runs:

```sh
shellcheck -x -P SCRIPTDIR $(find . -type f -name '*.sh' -not -path './.git/*')
npx --yes markdownlint-cli@0.49.1 '**/*.md' --ignore node_modules
yamllint -s .
reuse lint
bats test/unit
```

Keep changes small and single-purpose: one script does one job, no hidden
global state, fail loudly instead of swallowing errors. New scripts need
`bats` tests in `test/unit/`. Optionally register the repository at
[0pdd.com](https://www.0pdd.com/) to auto-file `@todo` code puzzles as
GitHub issues, per Yegor256's puzzle-driven development convention.

## License

MIT, see [LICENSE.txt](LICENSE.txt). Per-file license metadata follows the
[REUSE specification](https://reuse.software/); machine-readable info is in
[REUSE.toml](REUSE.toml) and [LICENSES/MIT.txt](LICENSES/MIT.txt).
