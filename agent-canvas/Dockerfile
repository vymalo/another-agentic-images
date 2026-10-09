# syntax=docker/dockerfile:1
#
# ghcr.io/vymalo/another-agentic-images/agent-canvas — OpenHands Agent Canvas with
# the Rust + Flutter/Dart + Node toolchains baked in.
#
# Why: the upstream image ships Node, Python, git and gcc, but no Rust or
# Flutter. Its agent then installs them itself at run time, into $HOME on the
# container filesystem, so every pod restart throws them away and the next
# task reinstalls them (minutes, and a hard dependency on upstream mirrors
# mid-task). Same "build once, heavy; reuse everywhere, fast" reasoning as
# github.com/vymalo/arc-runners.
#
# Layout rule: toolchains live under /opt, NEVER under $HOME. The deployment
# (home-os, charts/apps `agent-canvas`) mounts PVC subPaths over parts of
# /home/openhands (~/.openhands, ~/workspace, ~/.cargo), and a mount shadows
# whatever the image put at that path — a toolchain baked into ~/.cargo would
# be invisible at run time. Only the rustup launchers and the toolchains are
# in /opt; CARGO_HOME is deliberately left at its default (~/.cargo) so the
# crate registry/git caches and any `cargo install`ed tools land on the PVC
# and survive restarts.
#
# Pins mirror what the consuming repos' CI uses:
#   RUST_TOOLCHAIN   — vaam-apps rust-toolchain.toml (channel = "1.98.1").
#   FLUTTER_VERSION  — vymalo/arc-runners FLUTTER_VERSION.
#   SCCACHE_VERSION, CARGO_BINSTALL_VERSION — vymalo/arc-runners.
# pnpm is NOT pinned here: corepack resolves each project's own
# `packageManager` (vaam-apps: pnpm@10.33.0).
#
# amd64 is the only platform built (netcup is x86_64, and Flutter publishes
# no linux-arm64 SDK tarball).
#
# The install recipe (apt deps, rustup, cargo-binstall tools, sccache, obscura,
# Flutter, corepack, the npm CLIs, profile.d, the runtime user's config files) is NOT in
# this file: it is toolchains/install.sh, shared with the workspace image so the
# two provide exactly the same tools. This Dockerfile keeps the base, the pins,
# the ENV lines and the smoke test. Build from the REPO ROOT:
#   docker buildx build -f agent-canvas/Dockerfile .

ARG AGENT_CANVAS_VERSION=1.24.0
ARG AGENT_CANVAS_DIGEST=sha256:ad0829a7082a71ddfd2d16c1fae5a2172e4ca5a34eba7f03b69bd5b9b1bc54d7
FROM ghcr.io/openhands/agent-canvas:${AGENT_CANVAS_VERSION}@${AGENT_CANVAS_DIGEST}

ARG RUST_TOOLCHAIN=1.98.1
ARG FLUTTER_VERSION=3.44.4
ARG SCCACHE_VERSION=0.16.0
ARG CARGO_BINSTALL_VERSION=v1.23.0
# Coding-agent CLIs (for signing in and for terminal use). The ACP adapters
# Agent Canvas drives them through are NOT installed here — upstream already
# bundles them (see the install step). Resolved from the npm registry; bump
# deliberately (Claude Code's auto-updater is disabled — root-owned install).
ARG CLAUDE_CODE_VERSION=2.1.283
ARG CODEX_VERSION=0.158.0
# OpenCode (npm `opencode-ai`): the TUI/CLI, `opencode serve`/`web`, and
# `opencode acp` (ACP over stdio) — the coding engine another-agentic-platform's
# harness drives. Its postinstall selects the native binary, so scripts stay on.
ARG OPENCODE_VERSION=1.18.33
# obscura, a headless browser CLI with its own renderer (screenshots without
# Chromium or Playwright), and the sha256 of its obscura-x86_64-linux.tar.gz.
# Verified 2026-10-09: latest tag v0.2.4 (2026-10-04),
# https://github.com/h4ckf0r0day/obscura/releases/tag/v0.2.4; the release has
# no checksum file, so the digest is of the downloaded asset (two downloads
# hashed the same).
ARG OBSCURA_VERSION=0.2.4
ARG OBSCURA_SHA256=757e7b597ba5cdd53af9fc701e0a9b80f0a8d788f545d4f82ec9ad32db77f000
# The runtime user the base image already has. toolchains/install.sh creates
# that user's state (Flutter cache, pnpm config, mount-point parents) as it.
ARG TOOLCHAIN_USER=openhands
ARG TOOLCHAIN_HOME=/home/openhands

LABEL org.opencontainers.image.source="https://github.com/vymalo/another-agentic-images" \
      org.opencontainers.image.description="OpenHands Agent Canvas with Rust, Flutter/Dart and Node toolchains baked in" \
      org.opencontainers.image.licenses="MIT"

USER root
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV RUSTUP_HOME=/opt/rustup \
    FLUTTER_HOME=/opt/flutter \
    COREPACK_ENABLE_DOWNLOAD_PROMPT=0
# ~/.cargo/bin first so tools the agent `cargo install`s (persisted on the
# PVC) win over nothing else; the rustup launchers come from /opt/cargo/bin.
ENV PATH=/home/openhands/.cargo/bin:/opt/cargo/bin:/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:/opt/obscura/bin:${PATH}

# ---- Toolchains ----------------------------------------------------------
# Upstream ships Node (and corepack), Python, git and gcc, so the script only
# adds the toolchain packages, Rust, Flutter and the CLIs (NODE_VERSION is
# unset on purpose: no second Node).
#
# Coding agents: upstream already ships the ACP adapters Agent Canvas drives:
# /acp-node holds @agentclientprotocol/claude-agent-acp and
# @agentclientprotocol/codex-acp (plus @google/gemini-cli), exposed as
# /usr/local/bin/{claude-agent-acp,codex-acp,gemini} wrappers. Those are the
# versions Agent Canvas is released against, so the script leaves them alone
# (installing ours collided: "File exists: /usr/local/bin/codex-acp"). What
# upstream lacks is the standalone CLIs you sign in with — `claude` (/login)
# and `codex login` — so a user `npm i -g` hit EACCES on this root-owned prefix
# (and would be lost on restart anyway). The adapters read the same on-disk
# logins the CLIs write ($CLAUDE_CONFIG_DIR/.credentials.json,
# ~/.codex/auth.json), which the deployment persists; nothing here is baked
# into the image. OpenCode keeps its login in ~/.local/share/opencode/auth.json
# (plus sessions and logs there), config in ~/.config/opencode and cache in
# ~/.cache/opencode — also for the deployment to persist.
#
# GITHUB_TOKEN is an optional build secret that lifts the GitHub API rate
# limit for cargo-binstall; mounted, never layered, and not echoed.
RUN --mount=type=bind,source=toolchains,target=/toolchains \
    --mount=type=secret,id=github_token \
    sh /toolchains/install.sh

ENV DISABLE_AUTOUPDATER=1 \
    OPENCODE_DISABLE_AUTOUPDATE=1

USER openhands

# Smoke test, in a LOGIN shell — the environment the agent actually gets.
# obscura takes a real screenshot of a page Node serves on 127.0.0.1 (no network).
RUN bash -lc 'set -e; \
      rustc --version; cargo --version; cargo clippy --version; rustfmt --version; \
      just --version; cargo nextest --version; cargo deny --version; sccache --version; \
      flutter --version; dart --version; node --version; command -v pnpm; \
      claude --version; codex --version; opencode --version; command -v claude-agent-acp; command -v codex-acp; \
      obscura --version; \
      node -e "require(\"http\").createServer((q,s)=>s.writeHead(200,{\"content-type\":\"text/html\"}).end(\"<h1>obscura</h1>\")).listen(8787,\"127.0.0.1\")" & srv=$!; \
      for _ in $(seq 50); do curl -fs -o /dev/null http://127.0.0.1:8787/ && break; sleep 0.2; done; \
      obscura fetch http://127.0.0.1:8787/ --allow-private-network --screenshot /tmp/s.png; \
      kill "$srv"; test -s /tmp/s.png; rm -f /tmp/s.png; \
      test "$(corepack pnpm@10.33.0 config get store-dir)" = /home/openhands/.cache/pnpm-store; \
      test "$(pnpm config get store-dir)" = /home/openhands/.cache/pnpm-store; \
      test -O /home/openhands/.local/share; \
      test "$(id -u)" = 10001'
