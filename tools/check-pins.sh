#!/bin/sh
# Fails when the pins shared by the images differ between their Dockerfiles.
# Both images run toolchains/install.sh and must provide the same tools, so
# these ARGs must be equal in agent-canvas/Dockerfile and workspace/Dockerfile.
# Run from the repo root (both image workflows do, before building).
set -eu

a=agent-canvas/Dockerfile
b=workspace/Dockerfile
status=0
for name in RUST_TOOLCHAIN FLUTTER_VERSION SCCACHE_VERSION CARGO_BINSTALL_VERSION \
            CLAUDE_CODE_VERSION CODEX_VERSION OPENCODE_VERSION \
            OBSCURA_VERSION OBSCURA_SHA256; do
  va="$(sed -n "s/^ARG ${name}=//p" "$a")"
  vb="$(sed -n "s/^ARG ${name}=//p" "$b")"
  if [ -z "$va" ] || [ "$va" != "$vb" ]; then
    echo "pin mismatch: ${name}: ${a}='${va}' ${b}='${vb}'" >&2
    status=1
  fi
done
[ "$status" = 0 ] && echo "shared pins match"
exit "$status"
