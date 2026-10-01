#!/bin/sh
# Proves that an image works as a dev container base, the way a repository
# would use it: the devcontainer CLI reads the image's devcontainer.metadata
# label, starts a container from the image, and runs commands in it as the
# runtime user. Used by workspace.yml after the build; also runnable by hand
# against any image the local Docker daemon has (or can pull).
#
# What it checks:
#   1. `read-configuration --include-merged-configuration` merges the label:
#      remoteUser and containerUser are `agent`, updateRemoteUserUID is true.
#   2. `up` succeeds with a config that says only {"image": "<image>"}, and
#      reports remoteUser `agent`.
#   3. `exec`, in a login shell as the remote user: whoami is `agent`, the
#      toolchains and the coding-agent CLI are on PATH, the mount-point parents
#      (/work/workspaces, /workspaces) exist and are owned by uid 10001, and a
#      file created in the bind-mounted workspace folder is owned by the host
#      user (the uid sync that updateRemoteUserUID asks for), or by 10001 when
#      the host user is root (the CLI does not sync to uid 0).
# The container, and the per-run `vsc-*` image the CLI may build, are removed
# on exit.
#
# CLI pin: the latest on npm on 2026-10-01 (MIT, node >=20, no runtime
# dependencies). Override with DEVCONTAINERS_CLI_VERSION to try another.
# needs: docker, node (npx), jq.
# usage: tools/check-devcontainer.sh <image>
set -eu

usage() { echo "usage: $0 <image>" >&2; exit 2; }
die() { echo "check-devcontainer: $*" >&2; exit 1; }

[ $# -eq 1 ] || usage
image=$1
version="${DEVCONTAINERS_CLI_VERSION:-0.89.0}"
for cmd in docker npx jq; do
  command -v "$cmd" >/dev/null 2>&1 || die "missing prerequisite: $cmd"
done

dc() { npx --yes "@devcontainers/cli@${version}" "$@"; }

# `up` builds a small image on top of this one (it moves the user's uid), with
# `docker build`, which goes to the current buildx builder. A builder that is
# not the daemon's own (docker-container, as docker/setup-buildx-action creates)
# cannot see an image that is only in the local daemon and tries the registry.
driver="$(docker buildx inspect 2>/dev/null | sed -n 's/^Driver:[[:space:]]*//p' | head -n 1)"
if [ -n "$driver" ] && [ "$driver" != docker ]; then
  die "the current buildx builder uses the '${driver}' driver and cannot see local images; select the daemon's own builder, e.g. BUILDX_BUILDER=default"
fi

tmp="$(mktemp -d)"
ws="${tmp}/ws"
mkdir "$ws"
printf '{"image": "%s"}\n' "$image" > "${tmp}/dc.json"
# The CLI finds its container by this label (and sets it on creation).
idlabel="another-agentic-images.check=devcontainer-$$"

cleanup() {
  status=$?
  trap - EXIT
  ids="$(docker ps -aq --filter "label=${idlabel}" 2>/dev/null || true)"
  if [ -n "$ids" ]; then
    # shellcheck disable=SC2086 # one id per line, no spaces
    built="$(docker inspect --format '{{.Config.Image}}' $ids 2>/dev/null | sort -u | grep '^vsc-' || true)"
    # shellcheck disable=SC2086
    docker rm -f $ids >/dev/null 2>&1 || true
    # The CLI's uid-synced copy of the image, named vsc-<folder>-<hash>-uid.
    for b in $built; do docker rmi "$b" >/dev/null 2>&1 || true; done
  fi
  rm -rf "$tmp"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

# dcx <subcommand> [flags...]: the CLI against the temporary folder, with a
# config that is only the override file (as the coder drives it).
dcx() {
  sub=$1
  shift
  dc "$sub" --workspace-folder "$ws" --override-config "${tmp}/dc.json" "$@"
}

echo "== read-configuration: ${image}"
dcx read-configuration --include-merged-configuration > "${tmp}/conf.json" 2> "${tmp}/conf.err" \
  || { cat "${tmp}/conf.err" >&2; die "read-configuration failed"; }
jq -e '.mergedConfiguration | .remoteUser == "agent" and .containerUser == "agent" and .updateRemoteUserUID == true' \
  "${tmp}/conf.json" >/dev/null \
  || { jq -c '.mergedConfiguration' "${tmp}/conf.json" >&2; die "the devcontainer.metadata label was not merged as expected"; }
echo "merged configuration has remoteUser=agent containerUser=agent updateRemoteUserUID=true"

echo "== up"
# stdout is the result JSON; the log (stderr) is shown only on failure, as it is long.
dcx up --id-label "$idlabel" --no-lockfile > "${tmp}/up.json" 2> "${tmp}/up.err" \
  || { cat "${tmp}/up.err" >&2; die "devcontainer up failed"; }
jq -e '.outcome == "success" and .remoteUser == "agent"' "${tmp}/up.json" >/dev/null \
  || { cat "${tmp}/up.json" >&2; die "devcontainer up did not report success with remoteUser agent"; }
jq -c '{outcome, remoteUser, remoteWorkspaceFolder}' "${tmp}/up.json"

echo "== exec"
if [ "$(id -u)" = 0 ]; then
  # Root hosts get no uid sync, so `agent` keeps 10001: give it the folder.
  want_uid=10001
  chown "$want_uid" "$ws"
else
  want_uid="$(id -u)"
fi
# A login shell, which is how the agent's terminals run. `set -eu` makes the
# first failing check fail the exec (and so this script: exec passes the exit
# code through). The workspace folder is the bind mount of $ws.
# shellcheck disable=SC2016 # the script runs in the container: $-expansions are meant for it
dcx exec --id-label "$idlabel" bash -lc '
  set -eu
  test "$(whoami)" = agent
  test "$HOME" = /home/agent
  rustc --version
  cargo --version
  node --version
  git --version
  opencode --version
  test "$(stat -c %u /work/workspaces)" = 10001
  test "$(stat -c %u /workspaces)" = 10001
  pwd
  touch from-the-container
' || die "a command failed inside the dev container"
got="$(stat -c %u "${ws}/from-the-container")"
[ "$got" = "$want_uid" ] \
  || die "a file made in the workspace folder is owned by uid ${got} outside; expected ${want_uid}"
echo "ok: ${image} works as a dev container"
