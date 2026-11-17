#!/bin/sh
# Proves that the four language servers baked into an image answer: rust-analyzer,
# typescript-language-server, pyright and gopls. For each language the script runs
# the image as its runtime user, with no network, in a login shell, and drives the
# server over stdio with tools/lsp-probe.mjs against a tiny fixture from
# tools/lsp-fixtures/<language>/ (copied to a writable directory first):
#   initialize, didOpen of a file that holds ONE deliberate error, an error
#   diagnostic for that file, a definition request that lands on the known line,
#   shutdown, exit.
# Prints one line per language and exits non-zero when any of them missed.
# Used by agent-canvas.yml and workspace.yml after the build; also runnable by
# hand against any image the local Docker daemon has (or can pull).
#
# The slowest server is rust-analyzer (it loads the sysroot): its probe may wait
# 180 s. The fixtures need no network and the container gets none, so a server
# that wants to fetch something fails here instead of passing by luck.
# needs: docker.
# usage: tools/check-language-servers.sh <image>
set -eu

usage() { echo "usage: $0 <image>" >&2; exit 2; }

[ $# -eq 1 ] || usage
image=$1
command -v docker >/dev/null 2>&1 || { echo "check-language-servers: missing prerequisite: docker" >&2; exit 1; }

here="$(cd "$(dirname "$0")" && pwd)"
[ -f "${here}/lsp-probe.mjs" ] && [ -d "${here}/lsp-fixtures" ] || {
  echo "check-language-servers: lsp-probe.mjs or lsp-fixtures not found next to this script" >&2
  exit 1
}

# probe <label> <fixture dir> <timeout s> <probe flags and server...>
# The container script gets the fixture name and the probe's arguments as
# positional parameters ($0 is `bash`).
# shellcheck disable=SC2016 # the script runs in the container: $-expansions are meant for it
probe() {
  label=$1
  fixture=$2
  shift 2
  if out="$(docker run --rm --network none \
      --entrypoint bash \
      -e GOPROXY=off \
      -v "${here}/lsp-probe.mjs:/probe/lsp-probe.mjs:ro" \
      -v "${here}/lsp-fixtures:/probe/fixtures:ro" \
      "$image" -lc '
        set -eu
        d="$(mktemp -d)"
        cp -r "/probe/fixtures/$1/." "$d"
        shift
        cd "$d"
        exec node /probe/lsp-probe.mjs --root . "$@"
      ' bash "$fixture" "$@" 2>&1)"; then
    echo "ok   ${label}: $(printf '%s\n' "$out" | grep -E '^(diagnostic|definition):' | tr '\n' ' ')"
  else
    echo "FAIL ${label}"
    printf '%s\n' "$out" | sed 's/^/     /'
    failed=1
  fi
}

failed=0
probe rust-analyzer rust \
  --file src/main.rs --language rust --def 4:29 --expect src/util.rs:0 --timeout 180 -- rust-analyzer
probe typescript-language-server typescript \
  --file src/main.ts --language typescript --def 3:13 --expect src/util.ts:0 --timeout 60 -- typescript-language-server --stdio
probe pyright python \
  --file main.py --language python --def 3:7 --expect util.py:0 --timeout 60 -- pyright-langserver --stdio
probe gopls go \
  --file main.go --language go --def 6:14 --expect util.go:2 --timeout 90 -- gopls serve

[ "$failed" = 0 ] && echo "ok: all four language servers answer in ${image}"
exit "$failed"
