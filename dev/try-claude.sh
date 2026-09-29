#!/bin/sh
# End-to-end "agent edits a repo" loop with Claude Code against mock-anthropic.
#
# Run inside the workspace container:
#   docker compose run --rm workspace sh /dev-scripts/try-claude.sh
#
# Claude Code is wired by ANTHROPIC_BASE_URL + a dummy ANTHROPIC_API_KEY
# (compose.yaml). The mock answers the prompt below with a `Bash` tool_use, then,
# after the tool_result, with plain text.
set -eu
here=$(dirname "$0")
# shellcheck source=lib.sh
. "$here/lib.sh"

need claude
need git
reach "${ANTHROPIC_BASE_URL:?ANTHROPIC_BASE_URL is not set}"

repo=$(scratch_repo claude)
cd "$repo"
say "claude $(claude --version) in $repo"

# -p: print mode (no TUI). --allowedTools Bash: pre-approve the tool the mock
# calls. stdin is closed so the CLI does not wait for piped input.
say "claude -p '$TOOL_PROMPT'"
out=$(timeout 180 claude -p "$TOOL_PROMPT" --allowedTools Bash </dev/null 2>&1) || {
  printf '%s\n' "$out" >&2
  die "claude exited non-zero"
}
printf '%s\n' "$out"

check_result "$out" 'hello from mock-anthropic'
