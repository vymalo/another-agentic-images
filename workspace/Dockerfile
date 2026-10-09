# syntax=docker/dockerfile:1
#
# ghcr.io/vymalo/another-agentic-images/workspace — the same Rust + Flutter/Dart
# + Node toolchains and coding-agent CLIs as agent-canvas, on a bare Debian,
# without OpenHands Agent Canvas. The runtime image for coder agents that need
# real toolchains but not the Agent Canvas UI (another-adam-rs).
#
# Same recipe as agent-canvas: toolchains/install.sh, shared, so the two images
# provide exactly the same tools. The pins below MUST equal agent-canvas's
# (CI checks: tools/check-pins.sh). Build from the REPO ROOT:
#   docker buildx build -f workspace/Dockerfile .
#
# Layout rule (CLAUDE.md): toolchains live under /opt (Node under /usr/local),
# NEVER under $HOME, so a deployment can mount volumes over /home/agent without
# hiding them. CARGO_HOME stays at its default (~/.cargo) so crate caches and
# `cargo install`ed tools land wherever the deployment persists the home.
#
# No default agent process: ENTRYPOINT is tini only, and the coder image adds
# its binary on top. Not included: Python, the ACP adapters (claude-agent-acp,
# codex-acp — upstream Agent Canvas bundles those, the coder does not need them).
#
# Also a dev container base image: the devcontainer.metadata label below, and
# CI proves it with tools/check-devcontainer.sh.
#
# amd64 only (Flutter publishes no linux-arm64 SDK tarball).

# debian:trixie-slim (glibc, same family as upstream agent-canvas), pinned by
# tag and digest. Verified 2026-09-29: HEAD on Docker Hub's registry API
# (registry-1.docker.io/v2/library/debian/manifests/trixie-slim, OCI index
# accept header) returned this docker-content-digest.
ARG DEBIAN_TAG=trixie-slim
ARG DEBIAN_DIGEST=sha256:a99cfc517144bc59b1978475ec53b46ecabec7e43635402ee5b77cc54cd1b20a
FROM debian:${DEBIAN_TAG}@${DEBIAN_DIGEST}

# Shared pins: keep equal to agent-canvas/Dockerfile (see tools/check-pins.sh).
ARG RUST_TOOLCHAIN=1.98.1
ARG FLUTTER_VERSION=3.44.4
ARG SCCACHE_VERSION=0.16.0
ARG CARGO_BINSTALL_VERSION=v1.23.0
ARG CLAUDE_CODE_VERSION=2.1.283
ARG CODEX_VERSION=0.158.0
ARG OPENCODE_VERSION=1.18.33
# obscura, a headless browser CLI with its own renderer (screenshots without
# Chromium or Playwright), and the sha256 of its obscura-x86_64-linux.tar.gz.
# Verified 2026-10-09: latest tag v0.2.4 (2026-10-04),
# https://github.com/h4ckf0r0day/obscura/releases/tag/v0.2.4; the release has
# no checksum file, so the digest is of the downloaded asset (two downloads
# hashed the same).
ARG OBSCURA_VERSION=0.2.4
ARG OBSCURA_SHA256=757e7b597ba5cdd53af9fc701e0a9b80f0a8d788f545d4f82ec9ad32db77f000
# Node 24 (LTS "Krypton"), from nodejs.org, verified against its sha256.
# Verified 2026-09-29: https://nodejs.org/dist/v24.21.0/SHASUMS256.txt
# (node-v24.21.0-linux-x64.tar.xz); the downloaded tarball hashed the same.
ARG NODE_VERSION=24.21.0
ARG NODE_SHA256=fd8e59d5a511510f6a298afb548f18c7d2b1be404d8b4a27d94fbe49f56cb2d6
# The runtime user created below; toolchains/install.sh creates that user's
# state (Flutter cache, pnpm config, mount-point parents) as it.
ARG TOOLCHAIN_USER=agent
ARG TOOLCHAIN_HOME=/home/agent

LABEL org.opencontainers.image.source="https://github.com/vymalo/another-agentic-images" \
      org.opencontainers.image.description="Lean workspace: Rust, Flutter/Dart and Node toolchains plus the Claude Code, Codex and OpenCode CLIs on Debian" \
      org.opencontainers.image.licenses="MIT"

# Dev container metadata (containers.dev "image metadata"): the label that
# tools implementing the spec (the reference devcontainer CLI, among others)
# read, so a repository whose devcontainer.json says only
# {"image": ".../workspace:<tag>"} gets the right user. updateRemoteUserUID is
# the spec's default, written out on purpose: on a Linux host the CLI moves
# `agent` to the host user's uid when it bind-mounts a folder (and changes
# nothing when the uids already match). workspaceFolder is NOT an
# image-metadata property (the spec's table), so it cannot be set here; without
# it the CLI mounts the folder at /workspaces/<name>.
# Spec: https://containers.dev/implementors/spec/#image-metadata
LABEL devcontainer.metadata='[{"remoteUser":"agent","containerUser":"agent","updateRemoteUserUID":true}]'

USER root
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# ---- Base packages -----------------------------------------------------
# What toolchains/install.sh expects from its base (it adds unzip, pkg-config,
# clang, lld, cmake and protobuf-compiler itself). curl + ca-certificates +
# xz-utils: downloads and tarballs. gcc/g++/make/libc6-dev: rustc links with
# cc and build.rs compiles C/C++. libssl-dev: openssl-sys. zip + file: Flutter.
# git + openssh-client: the coder's mirrors and worktrees. tini: PID 1.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl xz-utils zip file \
      gcc g++ make libc6-dev libssl-dev \
      git openssh-client tini \
 && rm -rf /var/lib/apt/lists/*

# ---- Runtime user and working directory --------------------------------
# uid/gid 10001, the same as the openhands user in agent-canvas. /work is
# where the coder keeps its mirrors and worktrees.
RUN groupadd --gid 10001 agent \
 && useradd --uid 10001 --gid 10001 --create-home --home-dir /home/agent --shell /bin/bash agent \
 && install -d -o 10001 -g 10001 /work

ENV RUSTUP_HOME=/opt/rustup \
    FLUTTER_HOME=/opt/flutter \
    COREPACK_ENABLE_DOWNLOAD_PROMPT=0
# ~/.cargo/bin first so tools the agent `cargo install`s (persisted with the
# home) win; the rustup launchers come from /opt/cargo/bin. Node is in
# /usr/local/bin, already on Debian's PATH.
ENV PATH=/home/agent/.cargo/bin:/opt/cargo/bin:/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:/opt/obscura/bin:${PATH}

# ---- Toolchains ----------------------------------------------------------
# One RUN, one layer: the chown of /opt and every temporary download happen in
# it, so nothing is duplicated into a second layer. GITHUB_TOKEN is an optional
# build secret that lifts the GitHub API rate limit for cargo-binstall;
# mounted, never layered, and not echoed.
RUN --mount=type=bind,source=toolchains,target=/toolchains \
    --mount=type=secret,id=github_token \
    sh /toolchains/install.sh

ENV DISABLE_AUTOUPDATER=1 \
    OPENCODE_DISABLE_AUTOUPDATE=1

# Layout contract, rule 2: a container runtime creates the missing parents of a
# mount target as root. /workspaces is where the devcontainer CLI mounts a
# folder (/workspaces/<name>); /work/workspaces is the parent of the coder's
# per-run slots (<WORKSPACE_ROOT>/workspaces/<run>), which a dev container binds
# at the same path. Created in a layer of its own, after the toolchains, so the
# cached toolchain layer is reused.
RUN install -d -o 10001 -g 10001 /work/workspaces /workspaces

USER agent
WORKDIR /work

# Smoke test, in a LOGIN shell — the environment the agent actually gets. The
# same list as agent-canvas, minus the ACP adapters it gets from upstream, plus
# the workspace-specific checks (git, ssh, tini, the linker, /work). obscura
# takes a real screenshot of a page Node serves on 127.0.0.1 (no network).
RUN bash -lc 'set -e; \
      rustc --version; cargo --version; cargo clippy --version; rustfmt --version; \
      just --version; cargo nextest --version; cargo deny --version; sccache --version; \
      flutter --version; dart --version; node --version; command -v pnpm; \
      claude --version; codex --version; opencode --version; \
      obscura --version; \
      node -e "require(\"http\").createServer((q,s)=>s.writeHead(200,{\"content-type\":\"text/html\"}).end(\"<h1>obscura</h1>\")).listen(8787,\"127.0.0.1\")" & srv=$!; \
      for _ in $(seq 50); do curl -fs -o /dev/null http://127.0.0.1:8787/ && break; sleep 0.2; done; \
      obscura fetch http://127.0.0.1:8787/ --allow-private-network --screenshot /tmp/s.png; \
      kill "$srv"; test -s /tmp/s.png; rm -f /tmp/s.png; \
      test "$(corepack pnpm@10.33.0 config get store-dir)" = /home/agent/.cache/pnpm-store; \
      test "$(pnpm config get store-dir)" = /home/agent/.cache/pnpm-store; \
      test -O /home/agent/.local/share; \
      git --version; ssh -V; tini --version; cc --version; \
      test -w /work; \
      test -O /work/workspaces; test -O /workspaces; \
      test "$(id -u)" = 10001'

# PID 1 reaping and signal forwarding; no agent process. The coder image adds
# its binary as CMD.
ENTRYPOINT ["tini", "--"]
