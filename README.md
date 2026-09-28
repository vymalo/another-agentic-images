# another-agentic-images

Container images for the another-agentic family (another-agentic-platform, another-agentic-system) and for self-hosting [OpenHands](https://github.com/OpenHands/OpenHands) Agent Canvas, with the toolchains already in them.

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

**Bumping:** edit the `ARG`s at the top of [`agent-canvas/Dockerfile`](agent-canvas/Dockerfile). The upstream base is pinned by tag *and* digest. Merging to `main` publishes.

Consumed by `WhyThatFunction/home-os` (`charts/apps/values.yaml`, Application `agent-canvas`).
