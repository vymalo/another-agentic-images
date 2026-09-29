# another-agentic-images

Container images for the another-agentic family (another-agentic-platform, another-agentic-system) and for self-hosting [OpenHands](https://github.com/OpenHands/OpenHands) Agent Canvas, with the toolchains already in them.

| Image | What | Base |
|---|---|---|
| [`agent-canvas`](#agent-canvas) | OpenHands Agent Canvas plus the toolchains | upstream `ghcr.io/openhands/agent-canvas` |
| [`workspace`](#workspace) | The same toolchains, no Agent Canvas: the runtime for coder agents | `debian:trixie-slim` |

Both run the same install script, [`toolchains/install.sh`](toolchains/install.sh), so they provide identical tools. Build from the repo root: `docker buildx build -f <image>/Dockerfile .`

> Renamed from `vymalo/openhand-images` on 2026-09-28. Images now publish to `ghcr.io/vymalo/another-agentic-images/...`; the old `ghcr.io/vymalo/openhand-images/agent-canvas` package keeps its existing tags but receives no new ones.

## `agent-canvas`

`ghcr.io/vymalo/another-agentic-images/agent-canvas`: upstream `ghcr.io/openhands/agent-canvas` with these added:

| Ecosystem | Baked in |
|---|---|
| Rust | rustup + toolchain `1.98.1` (rustfmt, clippy, rust-src, llvm-tools-preview, `wasm32-unknown-unknown`), `just`, `cargo-nextest`, `cargo-deny`, `sccache` |
| Flutter/Dart | Flutter SDK `3.44.4` (bundles Dart), web artifacts precached |
| Node | upstream Node 24 + corepack shims (pnpm/yarn resolve each project's `packageManager`); pnpm store in `~/.cache/pnpm-store` |
| Coding agents | Claude Code `2.1.283`, Codex `0.158.0` and OpenCode `1.18.33` CLIs (sign in, terminal use; `opencode serve`/`web`/`acp`). The ACP adapters Agent Canvas drives Claude Code and Codex through (`claude-agent-acp`, `codex-acp`, plus `gemini`) come from upstream's `/acp-node`. Self-updaters are disabled — bump via the `ARG`s |
| Native deps | clang, lld, cmake, pkg-config, protobuf-compiler |

**Why:** the upstream image has no Rust or Flutter, so its agent installs them at run time into `$HOME` on the container filesystem. Every restart then throws them away.

**Layout contract:**
- Toolchains live under `/opt` (`RUSTUP_HOME=/opt/rustup`, launchers in `/opt/cargo/bin`, `/opt/flutter`), never under `$HOME`, so a deployment can mount persistent volumes over home directories without hiding them.
- `CARGO_HOME` stays at its default `~/.cargo`, so crate caches and `cargo install`ed tools follow wherever the deployment persists it.
- `PATH` is also exported from `/etc/profile.d/10-toolchains.sh`. Debian's `/etc/profile` resets `PATH` for login shells, which is what the agent's terminals are.

**Tags:**
- `<agent-canvas version>-<sha7>`: immutable. Pin this in deployments.
- `<agent-canvas version>` and `latest`: moving.

**Bumping:** edit the `ARG`s at the top of [`agent-canvas/Dockerfile`](agent-canvas/Dockerfile) (and the same shared pins in `workspace/Dockerfile`). The upstream base is pinned by tag *and* digest. Merging to `main` publishes.

Consumed by `WhyThatFunction/home-os` (`charts/apps/values.yaml`, Application `agent-canvas`).

## `workspace`

`ghcr.io/vymalo/another-agentic-images/workspace`: the toolchains of `agent-canvas` on a bare `debian:trixie-slim` (pinned by tag and digest), without OpenHands Agent Canvas. It is the runtime image for the adam-rs coder agent, and it is much smaller.

| Ecosystem | Baked in |
|---|---|
| Rust, Flutter/Dart, coding agents, native deps | Exactly the `agent-canvas` set above (the Rust, Flutter and CLI pins must match, and CI checks it) |
| Node | Node `24.21.0` from nodejs.org (pinned by version and sha256, in `/usr/local`) + corepack shims; pnpm store in `~/.cache/pnpm-store` |
| Base | git, openssh-client, ca-certificates, gcc/g++/make, libssl-dev, tini |

- User `agent` (uid/gid 10001), home `/home/agent`; `/work` is owned by it, for mirrors and worktrees.
- `ENTRYPOINT ["tini", "--"]` and no default process: the coder image adds its binary.
- Not included: the ACP adapters (`claude-agent-acp`, `codex-acp`), which `agent-canvas` gets from upstream, and Python.
- Same layout contract as `agent-canvas`, with `/home/agent` in place of `/home/openhands`.

**Tags:**
- `<rust toolchain>-<sha7>`, e.g. `1.98.1-<sha7>`: immutable. Pin this in deployments.
- `latest`: moving. There is no moving `<rust toolchain>` tag, because a Flutter or CLI bump would move it silently.

**Bumping:** edit the `ARG`s at the top of [`workspace/Dockerfile`](workspace/Dockerfile), and the same pins in `agent-canvas/Dockerfile`. New tools go in `toolchains/install.sh` and in both smoke tests. Merging to `main` publishes.
