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

LABEL org.opencontainers.image.source="https://github.com/vymalo/another-agentic-images" \
      org.opencontainers.image.description="OpenHands Agent Canvas with Rust, Flutter/Dart and Node toolchains baked in" \
      org.opencontainers.image.licenses="MIT"

USER root
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# ---- System packages the toolchains need ------------------------------
# unzip: Flutter/pub. pkg-config + libssl-dev (already in base): openssl-sys.
# clang + lld: bindgen / faster links. cmake: C deps built by build.rs.
# protobuf-compiler: prost/tonic codegen.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      unzip pkg-config clang lld cmake protobuf-compiler \
 && rm -rf /var/lib/apt/lists/*

ENV RUSTUP_HOME=/opt/rustup \
    FLUTTER_HOME=/opt/flutter \
    COREPACK_ENABLE_DOWNLOAD_PROMPT=0
# ~/.cargo/bin first so tools the agent `cargo install`s (persisted on the
# PVC) win over nothing else; the rustup launchers come from /opt/cargo/bin.
ENV PATH=/home/openhands/.cargo/bin:/opt/cargo/bin:/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:${PATH}

# ---- Rust --------------------------------------------------------------
# CARGO_HOME=/opt/cargo only for the install, so the launchers land in /opt.
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | CARGO_HOME=/opt/cargo sh -s -- -y --no-modify-path --profile minimal \
        --default-toolchain "${RUST_TOOLCHAIN}" \
        -c rustfmt -c clippy -c rust-src -c llvm-tools-preview \
        -t wasm32-unknown-unknown

# ---- Cargo tools (prebuilt via cargo-binstall; compile only as a last
#      resort). GITHUB_TOKEN is an optional build secret that lifts the
#      GitHub API rate limit; mounted, never layered, and not echoed. ------
RUN --mount=type=secret,id=github_token \
    set -eu; \
    if [ -s /run/secrets/github_token ]; then \
      GITHUB_TOKEN="$(cat /run/secrets/github_token)"; export GITHUB_TOKEN; \
    fi; \
    export CARGO_HOME=/opt/cargo; \
    tmp="$(mktemp -d)"; \
    curl --proto '=https' --tlsv1.2 -fsSL -o "${tmp}/cargo-binstall.tgz" \
      "https://github.com/cargo-bins/cargo-binstall/releases/download/${CARGO_BINSTALL_VERSION}/cargo-binstall-x86_64-unknown-linux-musl.tgz"; \
    tar -xzf "${tmp}/cargo-binstall.tgz" -C "${tmp}"; \
    install -m 0755 "${tmp}/cargo-binstall" /opt/cargo/bin/cargo-binstall; \
    rm -rf "${tmp}"; \
    cargo binstall -y --locked just cargo-nextest cargo-deny; \
    rm -rf /opt/cargo/registry /opt/cargo/git

# ---- sccache (binary only; the S3 backend is wired by the deployment) ---
RUN base="sccache-v${SCCACHE_VERSION}-x86_64-unknown-linux-musl" \
 && curl --proto '=https' --tlsv1.2 -fsSL \
      "https://github.com/mozilla/sccache/releases/download/v${SCCACHE_VERSION}/${base}.tar.gz" \
    | tar -xz -C /tmp \
 && install -m 0755 "/tmp/${base}/sccache" /usr/local/bin/sccache \
 && rm -rf "/tmp/${base}"

# ---- Flutter SDK (bundles Dart) ----------------------------------------
RUN curl --proto '=https' --tlsv1.2 -fsSL \
      "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
    | tar -xJ -C /opt \
 && git config --system --add safe.directory /opt/flutter

# ---- pnpm/yarn shims (corepack ships with the base image's Node) --------
RUN corepack enable

# ---- Coding agents: Claude Code and Codex CLIs --------------------------
# Upstream already ships the ACP adapters Agent Canvas drives: /acp-node holds
# @agentclientprotocol/claude-agent-acp and @agentclientprotocol/codex-acp (plus
# @google/gemini-cli), exposed as /usr/local/bin/{claude-agent-acp,codex-acp,
# gemini} wrappers. Those are the versions Agent Canvas is released against,
# so they are left alone (installing ours collided: "File exists:
# /usr/local/bin/codex-acp"). What upstream lacks is the standalone CLIs you
# sign in with — `claude` (/login) and `codex login` — so a user `npm i -g`
# hit EACCES on this root-owned prefix (and would be lost on restart anyway).
# The adapters read the same on-disk logins the CLIs write
# ($CLAUDE_CONFIG_DIR/.credentials.json, ~/.codex/auth.json), which the
# deployment persists; nothing here is baked into the image. OpenCode keeps its
# login in ~/.local/share/opencode/auth.json (plus sessions and logs there),
# config in ~/.config/opencode and cache in ~/.cache/opencode — also for the
# deployment to persist.
# Scripts stay enabled: Claude Code's and OpenCode's postinstalls select their
# native binaries. Self-updaters are off (root-owned install; bump via ARGs).
RUN npm install -g --no-fund --no-audit \
      "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
      "@openai/codex@${CODEX_VERSION}" \
      "opencode-ai@${OPENCODE_VERSION}" \
 && npm cache clean --force
ENV DISABLE_AUTOUPDATER=1 \
    OPENCODE_DISABLE_AUTOUPDATE=1

# The agent runs as openhands (10001) and may add toolchains/components or
# let Flutter update its cache at run time (lost on restart, but it must not
# fail on permissions).
RUN chown -R 10001:10001 /opt/rustup /opt/cargo /opt/flutter

# Login shells: Debian's /etc/profile resets PATH for non-root users, and the
# agent's terminals (tmux) run login shells, so the ENV above would be lost
# there. Re-export it from profile.d, which /etc/profile sources afterwards.
RUN printf '%s\n' \
      'export RUSTUP_HOME=/opt/rustup' \
      'export FLUTTER_HOME=/opt/flutter' \
      'export COREPACK_ENABLE_DOWNLOAD_PROMPT=0' \
      'export DISABLE_AUTOUPDATER=1' \
      'export OPENCODE_DISABLE_AUTOUPDATE=1' \
      'case ":$PATH:" in *:/opt/cargo/bin:*) ;; *) PATH="$HOME/.cargo/bin:/opt/cargo/bin:/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:$PATH" ;; esac' \
      'export PATH' \
    > /etc/profile.d/10-toolchains.sh

USER openhands

# Flutter's first run (tool snapshot) + the web artifacts, as the runtime
# user so its cache is owned correctly. Analytics off.
RUN flutter config --no-analytics --no-cli-animations \
 && dart --disable-analytics \
 && flutter precache --web --no-android --no-ios --no-linux --no-macos --no-windows --no-fuchsia

# pnpm's store location, in pnpm's OWN global config, not an
# `npm_config_store_dir` env var: npm reads every npm_config_* too and warns
# "Unknown env config store-dir" on each run. Two files, because the format
# changed between majors (verified): pnpm 10 reads the ini `rc` and ignores
# config.yaml; pnpm 12 reads `config.yaml` (storeDir) and ignores `rc`.
# corepack picks each project's own `packageManager` version, so both must
# work. ~/.cache is persisted by the deployment; ~/.config is not mounted,
# so these files survive from the image.
# Parents of the deployment's nested mount points, created here as openhands.
# A container runtime creates any missing parent of a mount target as root, so
# mounting ~/.local/share/opencode without this leaves ~/.local and
# ~/.local/share root-owned and every other tool writing there (pipx, uv
# tools, CLIs' data dirs) fails with EACCES.
RUN mkdir -p /home/openhands/.local/share /home/openhands/.local/bin

RUN mkdir -p /home/openhands/.config/pnpm \
 && printf 'store-dir=/home/openhands/.cache/pnpm-store\n' > /home/openhands/.config/pnpm/rc \
 && printf 'storeDir: /home/openhands/.cache/pnpm-store\n' > /home/openhands/.config/pnpm/config.yaml

# Smoke test, in a LOGIN shell — the environment the agent actually gets.
RUN bash -lc 'set -e; \
      rustc --version; cargo --version; cargo clippy --version; rustfmt --version; \
      just --version; cargo nextest --version; cargo deny --version; sccache --version; \
      flutter --version; dart --version; node --version; command -v pnpm; \
      claude --version; codex --version; opencode --version; command -v claude-agent-acp; command -v codex-acp; \
      test "$(corepack pnpm@10.33.0 config get store-dir)" = /home/openhands/.cache/pnpm-store; \
      test "$(pnpm config get store-dir)" = /home/openhands/.cache/pnpm-store; \
      test -O /home/openhands/.local/share; \
      test "$(id -u)" = 10001'
