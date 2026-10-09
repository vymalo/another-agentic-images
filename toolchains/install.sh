#!/bin/sh
# Shared toolchain recipe for every image in this repo.
#
# Installs Rust, Flutter/Dart, Node tooling, the coding-agent CLIs and the
# obscura headless browser, and writes /etc/profile.d/10-toolchains.sh. Each
# Dockerfile passes the pins and the runtime user as build ARGs (a RUN step sees
# ARGs as environment variables), then runs this script ONCE, as root, in a
# single RUN:
#
#   RUN --mount=type=bind,source=toolchains,target=/toolchains \
#       --mount=type=secret,id=github_token \
#       sh /toolchains/install.sh
#
# One RUN on purpose: the chown of /opt and every temporary download happen in
# the same layer, so nothing is duplicated into a second layer.
#
# The layout contract lives in CLAUDE.md and holds for every image built here:
# toolchains under /opt (never $HOME), CARGO_HOME left at ~/.cargo, PATH also in
# /etc/profile.d, tools configured in their own config files, npm postinstalls
# kept, self-updaters off. What stays in each Dockerfile: the base image, the
# runtime user, the ENV lines (a Dockerfile ENV cannot be produced by a script),
# the base packages listed under "Prerequisites", and the smoke test.
#
# Required environment (no defaults: a missing pin must fail the build):
#   RUST_TOOLCHAIN          rustup toolchain, e.g. 1.98.1
#   FLUTTER_VERSION         Flutter SDK (bundles Dart)
#   SCCACHE_VERSION         sccache, without the leading v
#   CARGO_BINSTALL_VERSION  cargo-binstall, with the leading v
#   CLAUDE_CODE_VERSION     @anthropic-ai/claude-code
#   CODEX_VERSION           @openai/codex
#   OPENCODE_VERSION        opencode-ai
#   OBSCURA_VERSION         obscura headless browser, without the leading v
#   OBSCURA_SHA256          sha256 of its obscura-x86_64-linux.tar.gz release asset
#   TOOLCHAIN_USER          runtime user; must already exist
#
# Optional environment:
#   TOOLCHAIN_HOME          runtime user's home         (default /home/$TOOLCHAIN_USER)
#   TOOLCHAIN_UID/_GID      owner of /opt toolchains    (default 10001 / 10001)
#   NODE_VERSION            install Node from nodejs.org into /usr/local. Unset
#   NODE_SHA256               when the base image already ships Node (agent-canvas).
#                             NODE_SHA256 is the linux-x64 .tar.xz digest; required
#                             with NODE_VERSION.
#   GITHUB_TOKEN_FILE       optional build secret that lifts the GitHub API rate
#                           limit for cargo-binstall (default /run/secrets/github_token).
#                           Read only inside the binstall step, never layered.
#
# Prerequisites the Dockerfile must provide (this script only adds the
# toolchain-specific packages below): curl, ca-certificates, git, tar, xz-utils,
# runuser (util-linux), plus what rustc needs to link: a C compiler (gcc or
# clang) and libssl-dev. Only the commands the script itself runs are checked.
#
# amd64 only: Flutter publishes no linux-arm64 SDK tarball.

set -eu

: "${RUST_TOOLCHAIN:?}" "${FLUTTER_VERSION:?}" "${SCCACHE_VERSION:?}" \
  "${CARGO_BINSTALL_VERSION:?}" "${CLAUDE_CODE_VERSION:?}" "${CODEX_VERSION:?}" \
  "${OPENCODE_VERSION:?}" "${OBSCURA_VERSION:?}" "${OBSCURA_SHA256:?}" \
  "${TOOLCHAIN_USER:?}"
TOOLCHAIN_HOME="${TOOLCHAIN_HOME:-/home/${TOOLCHAIN_USER}}"
TOOLCHAIN_UID="${TOOLCHAIN_UID:-10001}"
TOOLCHAIN_GID="${TOOLCHAIN_GID:-10001}"
GITHUB_TOKEN_FILE="${GITHUB_TOKEN_FILE:-/run/secrets/github_token}"

# runuser lives in /usr/sbin, which a base image's PATH may not include.
PATH="${PATH}:/usr/local/sbin:/usr/sbin:/sbin"
export PATH
[ "$(id -u)" = 0 ] || { echo "install.sh must run as root" >&2; exit 1; }
[ "$(uname -m)" = x86_64 ] || { echo "install.sh supports linux/amd64 only" >&2; exit 1; }
for cmd in curl git tar xz runuser; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "missing prerequisite: $cmd" >&2; exit 1; }
done
id "$TOOLCHAIN_USER" >/dev/null 2>&1 || { echo "user $TOOLCHAIN_USER does not exist" >&2; exit 1; }
[ -d "$TOOLCHAIN_HOME" ] || { echo "home $TOOLCHAIN_HOME does not exist" >&2; exit 1; }
if [ -n "${NODE_VERSION:-}" ]; then
  : "${NODE_SHA256:?NODE_SHA256 is required with NODE_VERSION}"
fi

export DEBIAN_FRONTEND=noninteractive
export RUSTUP_HOME=/opt/rustup
export FLUTTER_HOME=/opt/flutter
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# curl with the flags every download here uses; -f so an HTTP error fails.
fetch() { # fetch <url> <dest>
  curl --proto '=https' --tlsv1.2 -fsSL -o "$2" "$1"
}

# ---- System packages the toolchains need -------------------------------
# unzip: Flutter/pub. pkg-config (+ libssl-dev from the prerequisites):
# openssl-sys. clang + lld: bindgen / faster links. cmake: C deps built by
# build.rs. protobuf-compiler: prost/tonic codegen.
apt-get update
apt-get install -y --no-install-recommends \
  unzip pkg-config clang lld cmake protobuf-compiler
rm -rf /var/lib/apt/lists/*

# ---- Node (only when the base image has none) ---------------------------
# nodejs.org's tarball, verified against a pinned sha256, extracted over
# /usr/local exactly like the official node image. Node 24 bundles corepack.
if [ -n "${NODE_VERSION:-}" ]; then
  node_tar="node-v${NODE_VERSION}-linux-x64.tar.xz"
  fetch "https://nodejs.org/dist/v${NODE_VERSION}/${node_tar}" "${work}/${node_tar}"
  (cd "$work" && printf '%s  %s\n' "$NODE_SHA256" "$node_tar" | sha256sum -c -)
  tar -xJf "${work}/${node_tar}" -C /usr/local --strip-components=1 --no-same-owner
  rm -f /usr/local/CHANGELOG.md /usr/local/LICENSE /usr/local/README.md
  rm -f "${work}/${node_tar}"
  [ "$(node --version)" = "v${NODE_VERSION}" ] || { echo "node version mismatch" >&2; exit 1; }
fi
command -v node >/dev/null 2>&1 || { echo "no node: set NODE_VERSION/NODE_SHA256 or use a base that ships it" >&2; exit 1; }
command -v corepack >/dev/null 2>&1 || { echo "node has no corepack" >&2; exit 1; }

# ---- Rust --------------------------------------------------------------
# CARGO_HOME=/opt/cargo only for the install, so the launchers land in /opt.
fetch https://sh.rustup.rs "${work}/rustup-init.sh"
CARGO_HOME=/opt/cargo sh "${work}/rustup-init.sh" -y --no-modify-path --profile minimal \
  --default-toolchain "${RUST_TOOLCHAIN}" \
  -c rustfmt -c clippy -c rust-src -c llvm-tools-preview \
  -t wasm32-unknown-unknown

# ---- Cargo tools (prebuilt via cargo-binstall; compile only as a last
#      resort). The token is exported inside this subshell only and not echoed.
(
  if [ -s "$GITHUB_TOKEN_FILE" ]; then
    GITHUB_TOKEN="$(cat "$GITHUB_TOKEN_FILE")"
    export GITHUB_TOKEN
  fi
  export CARGO_HOME=/opt/cargo
  fetch "https://github.com/cargo-bins/cargo-binstall/releases/download/${CARGO_BINSTALL_VERSION}/cargo-binstall-x86_64-unknown-linux-musl.tgz" \
    "${work}/cargo-binstall.tgz"
  tar -xzf "${work}/cargo-binstall.tgz" -C "$work"
  install -m 0755 "${work}/cargo-binstall" /opt/cargo/bin/cargo-binstall
  rm -f "${work}/cargo-binstall" "${work}/cargo-binstall.tgz"
  env PATH="/opt/cargo/bin:${PATH}" cargo binstall -y --locked just cargo-nextest cargo-deny
  rm -rf /opt/cargo/registry /opt/cargo/git
)

# ---- sccache (binary only; the S3 backend is wired by the deployment) ---
sccache_base="sccache-v${SCCACHE_VERSION}-x86_64-unknown-linux-musl"
fetch "https://github.com/mozilla/sccache/releases/download/v${SCCACHE_VERSION}/${sccache_base}.tar.gz" \
  "${work}/sccache.tar.gz"
tar -xzf "${work}/sccache.tar.gz" -C "$work"
install -m 0755 "${work}/${sccache_base}/sccache" /usr/local/bin/sccache
rm -rf "${work:?}/${sccache_base:?}" "${work}/sccache.tar.gz"

# ---- obscura (headless browser with its own renderer, no Chromium) -------
# For screenshots of a site the agent serves on 127.0.0.1:
#   obscura fetch http://127.0.0.1:3000 --allow-private-network --screenshot shot.png
# The release asset carries `obscura` and `obscura-worker` (which `obscura
# scrape` looks for next to `obscura`), so both go in one directory. They need
# only glibc 2.35+ and libgcc_s, and bundle their fonts (Liberation, DejaVu,
# Noto Color Emoji): no fontconfig or font packages. Upstream publishes no
# checksum file; OBSCURA_SHA256 is the asset's own digest.
obscura_tar="obscura-x86_64-linux.tar.gz"
fetch "https://github.com/h4ckf0r0day/obscura/releases/download/v${OBSCURA_VERSION}/${obscura_tar}" \
  "${work}/${obscura_tar}"
(cd "$work" && printf '%s  %s\n' "$OBSCURA_SHA256" "$obscura_tar" | sha256sum -c -)
install -d /opt/obscura/bin
tar -xzf "${work}/${obscura_tar}" -C /opt/obscura/bin --no-same-owner obscura obscura-worker
rm -f "${work}/${obscura_tar}"
[ "$(/opt/obscura/bin/obscura --version)" = "obscura ${OBSCURA_VERSION}" ] \
  || { echo "obscura version mismatch" >&2; exit 1; }

# ---- Flutter SDK (bundles Dart) ----------------------------------------
fetch "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
  "${work}/flutter.tar.xz"
tar -xJf "${work}/flutter.tar.xz" -C /opt
rm -f "${work}/flutter.tar.xz"
git config --system --add safe.directory /opt/flutter

# ---- pnpm/yarn shims ----------------------------------------------------
corepack enable

# ---- Coding agents: Claude Code, Codex and OpenCode CLIs -----------------
# Scripts stay enabled: Claude Code's and OpenCode's postinstalls select their
# native binaries. Their self-updaters are switched off below (root-owned
# install; versions move only through the pins).
npm install -g --no-fund --no-audit \
  "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
  "@openai/codex@${CODEX_VERSION}" \
  "opencode-ai@${OPENCODE_VERSION}"
npm cache clean --force

# The agent runs as the runtime user (uid 10001) and may add toolchains or
# components, or let Flutter update its cache at run time (lost on restart,
# but it must not fail on permissions).
chown -R "${TOOLCHAIN_UID}:${TOOLCHAIN_GID}" /opt/rustup /opt/cargo /opt/flutter

# Login shells: Debian's /etc/profile resets PATH for non-root users, and agent
# terminals run login shells, so the Dockerfile's ENV would be lost there.
# Re-export it from profile.d, which /etc/profile sources afterwards.
cat > /etc/profile.d/10-toolchains.sh <<'EOF'
export RUSTUP_HOME=/opt/rustup
export FLUTTER_HOME=/opt/flutter
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
export DISABLE_AUTOUPDATER=1
export OPENCODE_DISABLE_AUTOUPDATE=1
case ":$PATH:" in *:/opt/cargo/bin:*) ;; *) PATH="$HOME/.cargo/bin:/opt/cargo/bin:/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:/opt/obscura/bin:$PATH" ;; esac
export PATH
EOF

# ---- Runtime-user state, created as that user ---------------------------
as_user() {
  runuser -u "$TOOLCHAIN_USER" -- env \
    HOME="$TOOLCHAIN_HOME" \
    PATH="/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:${PATH}" \
    RUSTUP_HOME=/opt/rustup FLUTTER_HOME=/opt/flutter \
    "$@"
}

# Flutter's first run (tool snapshot) + the web artifacts, as the runtime user
# so its cache is owned correctly. Analytics off.
as_user flutter config --no-analytics --no-cli-animations
as_user dart --disable-analytics
as_user flutter precache --web --no-android --no-ios --no-linux --no-macos --no-windows --no-fuchsia

# Parents of the deployment's nested mount points, created as the runtime user.
# A container runtime creates any missing parent of a mount target as root, so
# mounting ~/.local/share/opencode without this leaves ~/.local and
# ~/.local/share root-owned and every other tool writing there (pipx, uv
# tools, CLIs' data dirs) fails with EACCES.
as_user mkdir -p "${TOOLCHAIN_HOME}/.local/share" "${TOOLCHAIN_HOME}/.local/bin"

# pnpm's store location, in pnpm's OWN global config, not an
# `npm_config_store_dir` env var: npm reads every npm_config_* too and warns
# "Unknown env config store-dir" on each run. Two files, because the format
# changed between majors (verified): pnpm 10 reads the ini `rc` and ignores
# config.yaml; pnpm 12 reads `config.yaml` (storeDir) and ignores `rc`.
# corepack picks each project's own `packageManager` version, so both must work.
as_user mkdir -p "${TOOLCHAIN_HOME}/.config/pnpm"
printf 'store-dir=%s/.cache/pnpm-store\n' "$TOOLCHAIN_HOME" \
  | as_user tee "${TOOLCHAIN_HOME}/.config/pnpm/rc" >/dev/null
printf 'storeDir: %s/.cache/pnpm-store\n' "$TOOLCHAIN_HOME" \
  | as_user tee "${TOOLCHAIN_HOME}/.config/pnpm/config.yaml" >/dev/null
