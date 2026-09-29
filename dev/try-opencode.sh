#!/bin/sh
# End-to-end "agent edits a repo" loop with OpenCode against mock-openai.
#
# Run inside the workspace container:
#   docker compose run --rm workspace sh /dev-scripts/try-opencode.sh
#
# OpenCode gets its provider from OPENCODE_CONFIG_CONTENT (compose.yaml): a
# custom @ai-sdk/openai-compatible provider at http://mock-openai:8080/v1. The
# mock answers the prompt below with a `bash` tool call
# (printf ... > hello.txt), then, once the tool result comes back, with plain
# text. Exits 0 only if the file exists and the final text was printed.
set -eu
here=$(dirname "$0")
# shellcheck source=lib.sh
. "$here/lib.sh"

need opencode
need git
: "${MOCK_OPENAI_URL:?MOCK_OPENAI_URL is not set}"
reach "${MOCK_OPENAI_URL%/v1}"

repo=$(scratch_repo opencode)
cd "$repo"
say "opencode $(opencode --version) in $repo"

say "opencode run '$TOOL_PROMPT'"
out=$(timeout 180 opencode run "$TOOL_PROMPT" 2>&1) || {
  printf '%s\n' "$out" >&2
  die "opencode exited non-zero"
}
printf '%s\n' "$out"

check_result "$out" 'hello from mock-openai'
