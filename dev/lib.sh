#!/bin/sh
# Shared helpers for the dev/try-*.sh scripts (sourced, POSIX sh). They run
# INSIDE the workspace container (or agent-canvas) with the mocks wired by
# compose.yaml; see README.md "Local testing".

# The prompt marker that makes a mock answer with a tool call (writing
# hello.txt) instead of plain text. Documented in dev/wiremock/README.md.
# shellcheck disable=SC2034  # used by the scripts that source this file
TOOL_PROMPT='create hello.txt [mock:tool-call]'
# Every mock reply to the tool-call prompt ends with this sentence.
# shellcheck disable=SC2034  # used by check_result and the sourcing scripts
DONE_TEXT='Done. I created hello.txt.'

say() { printf '==> %s\n' "$*"; }
die() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# need <command>: the CLI must be on PATH (a login shell sets it up).
need() {
  command -v "$1" >/dev/null 2>&1 || die "$1 not found on PATH (is this the workspace container? try 'bash -l')"
}

# reach <url>: the mock must answer its health endpoint.
reach() {
  curl -fsS --max-time 5 "$1/__admin/health" >/dev/null 2>&1 || die "cannot reach $1 (are the mocks up? docker compose up -d --wait)"
}

# scratch_repo <label>: a fresh git repository under /work (or $WORK_DIR); prints its path.
scratch_repo() {
  dir=$(mktemp -d "${WORK_DIR:-/work}/try-$1.XXXXXX") || die "cannot create a scratch directory under ${WORK_DIR:-/work}"
  git -C "$dir" init -q
  git -C "$dir" -c user.name=Mock -c user.email=mock@example.invalid commit -q --allow-empty -m init
  printf '%s\n' "$dir"
}

# check_result <agent-output> <expected-content>: the edit landed and the agent said so.
# Runs in the scratch repository.
check_result() {
  [ -f hello.txt ] || die "hello.txt was not created; agent output was: $1"
  grep -qF "$2" hello.txt || die "hello.txt does not contain '$2'"
  printf '%s\n' "$1" | grep -qF "$DONE_TEXT" || die "agent output lacks '$DONE_TEXT'"
  git status --short | grep -q 'hello.txt' || die "git does not see hello.txt"
  say "ok: hello.txt created ($(cat hello.txt))"
}
