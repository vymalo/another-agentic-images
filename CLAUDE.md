# Agent guide — another-agentic-images

`AGENTS.md` is a symlink to this file. Edit `CLAUDE.md` only.

## What this is

Container images for the another-agentic family and for self-hosting OpenHands
Agent Canvas, with toolchains baked in. Renamed from `vymalo/openhand-images`
on 2026-09-28.

| Image | Source | Consumed by |
|---|---|---|
| `ghcr.io/vymalo/another-agentic-images/agent-canvas` | `agent-canvas/Dockerfile` | `WhyThatFunction/home-os`, `charts/apps/values.yaml`, Application `agent-canvas` (netcup) |
| `ghcr.io/vymalo/another-agentic-images/workspace` | `workspace/Dockerfile` | the adam-rs coder agent (`vymalo/another-adam-rs`) |

`agent-canvas` is upstream `ghcr.io/openhands/agent-canvas` (pinned by tag
**and** digest) plus Rust, Flutter/Dart, corepack, sccache, and the Claude Code,
Codex and OpenCode CLIs. `workspace` is the same toolchains on a bare
`debian:trixie-slim` (pinned by tag **and** digest) with Node 24, git, ssh and
tini, no Agent Canvas, user `agent` (10001), `/work`, and no agent process.

**Both run one script, `toolchains/install.sh`** (bind-mounted by each
Dockerfile, run once as root). The recipe lives there; each Dockerfile keeps its
base, the version `ARG`s, the `ENV` lines and the smoke test. Every tool change
goes in the script, and in **both** Dockerfiles' pins and smoke tests.
`tools/check-pins.sh` (run by both workflows) fails if the shared pins differ.

## Layout contract — every change must keep these true

1. **Toolchains live under `/opt`, never under `$HOME`** (Node, when the base
   has none, goes into `/usr/local`). The deployment mounts
   persistent volumes over parts of `/home/openhands`, and a mount hides what
   the image put there.
2. **Pre-create the parents of nested mount points as the runtime user**
   (`openhands`; `agent` in workspace). A container
   runtime creates missing parents of a mount target as root (e.g. mounting
   `~/.local/share/opencode` would leave `~/.local/share` root-owned).
3. **`PATH` and tool env go in `/etc/profile.d/10-toolchains.sh` as well as
   `ENV`.** Debian's `/etc/profile` resets `PATH` for login shells, and agent
   terminals are login shells.
4. **Configure each tool in its own config file,** not via `npm_config_*` env
   vars (npm reads them all and warns). Test the versions projects actually pin
   (pnpm 10 and 12 read different files).
5. **Global npm installs keep their postinstall scripts** (Claude Code and
   OpenCode select native binaries there) and **self-updaters are off**
   (`DISABLE_AUTOUPDATER`, `OPENCODE_DISABLE_AUTOUPDATE`); versions move only
   through `ARG`s.
6. **Don't reinstall what upstream ships** (the ACP adapters in `/acp-node`).
7. **The last `RUN` is the smoke test**, in a login shell as uid 10001. Every
   added tool gets a line there, in each image's Dockerfile.
8. **One recipe.** `toolchains/install.sh` is the only place that installs
   toolchains, and it runs in a single `RUN` (a later `chown -R` in its own layer
   would copy every file again). Keep its bind-mounted directory to that script:
   any file there invalidates the cached toolchain layer.

Skill: `change-image` (`.agents/skills/change-image/SKILL.md`).

## Release flow

```mermaid
sequenceDiagram
  participant PR as Pull request
  participant CI as agent-canvas.yml
  participant GHCR as ghcr.io
  participant HO as home-os
  PR->>CI: build (no push) incl. smoke test
  CI-->>PR: green
  PR->>CI: merge → build on main
  CI->>GHCR: push 1.24.0-<sha7>, 1.24.0, latest
  HO->>GHCR: bump charts/apps/values.yaml to 1.24.0-<sha7>
```

`workspace.yml` mirrors this for the `workspace` image. Its tags are
`<RUST_TOOLCHAIN>-<sha7>` (immutable, e.g. `1.98.1-<sha7>`) and `latest`. There
is no moving `<RUST_TOOLCHAIN>` tag, because a Flutter or CLI bump would move it
silently. PRs export an OCI tarball to report the image size; `main` reports the
pushed size. Both image builds use the **repo root** as context.

- **Don't merge before the PR's own build is green** (both builds, when
  `toolchains/` changes) — the smoke test is the only proof the tools work as
  the runtime user.
- Deployments pin the immutable `<agent-canvas version>-<sha7>` tag.
- A new package path (e.g. `.../workspace`) must be checked for **anonymous
  pull** before a deployment points at it (swap the image name below):

```sh
TOKEN=$(curl -s "https://ghcr.io/token?scope=repository:vymalo/another-agentic-images/agent-canvas:pull" | python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])')
curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $TOKEN" \
  -H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json' \
  https://ghcr.io/v2/vymalo/another-agentic-images/agent-canvas/manifests/<tag>
```

## Commands

```sh
docker buildx build --check --platform linux/amd64 -f agent-canvas/Dockerfile .   # lint (repo root is the context)
docker buildx build --check --platform linux/amd64 -f workspace/Dockerfile .      # lint
sh -n toolchains/install.sh && sh tools/check-pins.sh                             # syntax; shared pins equal
sh tools/image-size.sh --layers <registry/name:tag | oci.tar>                     # compressed size (bytes on stdout) + per-layer table (stderr)
git config core.hooksPath .githooks                                               # once per clone
```

## Commits

Conventional Commits, enforced by `tools/commit-lint.sh` (local hook and CI).

## Pull requests

- Branch + PR against `main`; `gh`/`git push` via `zsh -i -c '…'`.
- Body follows `.github/PULL_REQUEST_TEMPLATE.md` (AI governance; the
  `AI Governance` check enforces it).
- Checks: `AI Governance`, `Commit Lint`, and `Build agent-canvas` / `Build workspace` when an image or `toolchains/` changes.
