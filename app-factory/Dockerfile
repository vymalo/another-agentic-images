# syntax=docker/dockerfile:1
#
# ghcr.io/vymalo/another-agentic-images/app-factory — workspace image extended
# with App Factory tooling (Fespalier CLI, CrateStack CLI, SQLx CLI, and Android
# SDK cmdline-tools + OpenJDK 21).
#
# Build from the REPO ROOT:
#   docker buildx build -f app-factory/Dockerfile .
# Or against a locally built workspace image:
#   docker buildx build -f app-factory/Dockerfile --build-arg BASE_IMAGE=another-agentic-images/workspace:local .
#
# amd64 only (inherited from workspace: Flutter and x86_64 release tarballs).

ARG BASE_IMAGE=ghcr.io/vymalo/another-agentic-images/workspace:1.98.1-8c297d3@sha256:b465808bfb8a1baae5e59a429bf292726b021e3b37322f759dbda3ee2c57ed67
FROM ${BASE_IMAGE}

ARG TOOLCHAIN_UID=10001
ARG TOOLCHAIN_GID=10001

# Fespalier CLI v0.26.0 (https://github.com/fespalier/fespalier/releases/tag/v0.26.0)
ARG FSP_VERSION=0.26.0
ARG FSP_SHA256=3eb148210531af6d75fee91df89a4d29ae2804fbb900d2f8195ef89ed0d16eb5

# CrateStack CLI 0.20.4 (https://github.com/cratestack/cratestack/releases/tag/v0.20.4)
ARG CRATESTACK_VERSION=0.20.4
ARG CRATESTACK_SHA256=880589cacd966be3b80040ff1950e9cd0ea876735d147b42fb955bfa86b72cbf

# SQLx CLI 0.9.1 (crates.io max_stable_version as of 2026-11-18, postgres + rustls)
ARG SQLX_CLI_VERSION=0.9.1

# Android SDK cmdline-tools;23.0 + Flutter 3.44.4 default SDK (API 36)
ARG ANDROID_CMDLINE_TOOLS_ARCHIVE=commandlinetools-linux-16111833_latest.zip
ARG ANDROID_CMDLINE_TOOLS_SHA256=0877a1d048fe4a24efe2eff536ca4223f7adeb58648bb81909d33c446918cfa8
ARG ANDROID_COMPILE_SDK=36
ARG ANDROID_BUILD_TOOLS=36.1.0

LABEL org.opencontainers.image.source="https://github.com/vymalo/another-agentic-images" \
      org.opencontainers.image.description="App Factory workspace: Rust, Flutter/Dart, Node, fsp, cratestack, sqlx, and Android SDK cmdline-tools on Debian" \
      org.opencontainers.image.licenses="MIT"

USER root
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64 \
    ANDROID_HOME=/opt/android-sdk \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    PATH=${PATH}:/opt/app-factory/bin:/opt/android-sdk/cmdline-tools/latest/bin:/opt/android-sdk/platform-tools

RUN work="$(mktemp -d)" \
 && trap 'rm -rf "$work"' EXIT \
 && export DEBIAN_FRONTEND=noninteractive \
 && apt-get update \
 && apt-get install -y --no-install-recommends openjdk-21-jdk-headless \
 && rm -rf /var/lib/apt/lists/* \
 && install -d /opt/app-factory/bin \
 && curl --proto '=https' --tlsv1.2 -fsSL -o "${work}/fsp.tar.gz" \
      "https://github.com/fespalier/fespalier/releases/download/v${FSP_VERSION}/fsp-x86_64-unknown-linux-gnu.tar.gz" \
 && (cd "$work" && printf '%s  fsp.tar.gz\n' "$FSP_SHA256" | sha256sum -c -) \
 && tar -xzf "${work}/fsp.tar.gz" -C /opt/app-factory/bin --no-same-owner fsp \
 && chmod 0755 /opt/app-factory/bin/fsp \
 && curl --proto '=https' --tlsv1.2 -fsSL -o "${work}/cratestack.tar.gz" \
      "https://github.com/cratestack/cratestack/releases/download/v${CRATESTACK_VERSION}/cratestack-cli-x86_64-unknown-linux-gnu-v${CRATESTACK_VERSION}.tar.gz" \
 && (cd "$work" && printf '%s  cratestack.tar.gz\n' "$CRATESTACK_SHA256" | sha256sum -c -) \
 && tar -xzf "${work}/cratestack.tar.gz" -C /opt/app-factory/bin --no-same-owner cratestack \
 && chmod 0755 /opt/app-factory/bin/cratestack \
 && CARGO_HOME="${work}/cargo-home" CARGO_INSTALL_ROOT=/opt/cargo \
      cargo install --locked --version "${SQLX_CLI_VERSION}" sqlx-cli \
        --no-default-features --features postgres,rustls \
 && install -d /opt/android-sdk/cmdline-tools \
 && curl --proto '=https' --tlsv1.2 -fsSL -o "${work}/${ANDROID_CMDLINE_TOOLS_ARCHIVE}" \
      "https://dl.google.com/android/repository/${ANDROID_CMDLINE_TOOLS_ARCHIVE}" \
 && (cd "$work" && printf '%s  %s\n' "$ANDROID_CMDLINE_TOOLS_SHA256" "$ANDROID_CMDLINE_TOOLS_ARCHIVE" | sha256sum -c -) \
 && unzip -q "${work}/${ANDROID_CMDLINE_TOOLS_ARCHIVE}" -d "${work}/android-unpack" \
 && mv "${work}/android-unpack/cmdline-tools" /opt/android-sdk/cmdline-tools/latest \
 && ( set +o pipefail; yes | /opt/android-sdk/cmdline-tools/latest/bin/sdkmanager --sdk_root=/opt/android-sdk --licenses >/dev/null ) \
 && /opt/android-sdk/cmdline-tools/latest/bin/sdkmanager --sdk_root=/opt/android-sdk \
      "platform-tools" \
      "platforms;android-${ANDROID_COMPILE_SDK}" \
      "build-tools;${ANDROID_BUILD_TOOLS}" \
 && test -d /opt/android-sdk/licenses \
 && rm -rf /root/.android \
 && chown -R "${TOOLCHAIN_UID}:${TOOLCHAIN_GID}" /opt/app-factory /opt/android-sdk /opt/cargo/bin/sqlx /opt/cargo/bin/cargo-sqlx \
 && printf '%s\n' \
      'export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64' \
      'export ANDROID_HOME=/opt/android-sdk' \
      'export ANDROID_SDK_ROOT=/opt/android-sdk' \
      'case ":$PATH:" in *:/opt/app-factory/bin:*) ;; *) PATH="$PATH:/opt/app-factory/bin:/opt/android-sdk/cmdline-tools/latest/bin:/opt/android-sdk/platform-tools" ;; esac' \
      'export PATH' \
      > /etc/profile.d/20-app-factory.sh \
 && chmod 0644 /etc/profile.d/20-app-factory.sh

USER agent
WORKDIR /work

# Login-shell smoke test as UID 10001
RUN bash -lc 'set -e; \
      test "$(id -u)" = 10001; test "$(whoami)" = agent; \
      rust-analyzer --version; rustc --version; cargo --version; \
      flutter --version; dart --version; dart language-server --help >/dev/null; \
      fsp --version; \
      test "$(cratestack --version)" = "cratestack 0.20.4"; \
      CRATESTACK_REQUIRE_VERSION=0.20.4 cratestack --version >/dev/null; \
      sqlx --version; cargo sqlx --version; \
      java -version; test -d "$JAVA_HOME"; \
      sdkmanager --version; adb --version; \
      test "$ANDROID_HOME" = /opt/android-sdk; test "$ANDROID_SDK_ROOT" = /opt/android-sdk; \
      test -d "/opt/android-sdk/platforms/android-${ANDROID_COMPILE_SDK}"; \
      test -d "/opt/android-sdk/build-tools/${ANDROID_BUILD_TOOLS}"; \
      test -d /opt/android-sdk/licenses; \
      test -O /opt/app-factory; test -O /opt/android-sdk; test -w /opt/android-sdk; \
      test -O /cache; test -w /cache; test -k /cache; test -z "$(ls -A /cache)"; \
      env -i HOME=/home/agent /bin/bash -lc "command -v fsp cratestack sqlx sdkmanager adb dart rust-analyzer >/dev/null && test \"\$ANDROID_HOME\" = /opt/android-sdk"; \
      for k8s_bin in kubectl helm kustomize cnpg; do \
        if command -v "$k8s_bin" >/dev/null 2>&1; then echo "unexpected k8s binary: $k8s_bin" >&2; exit 1; fi; \
      done; \
      rm -rf /home/agent/.android'

ENTRYPOINT ["tini", "--"]
