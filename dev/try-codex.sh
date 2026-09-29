#!/bin/sh
# End-to-end "agent edits a repo" loop with Codex against mock-openai.
#
# Run inside the workspace container:
#   docker compose run --rm workspace sh /dev-scripts/try-codex.sh
#
# Codex does not read OPENAI_BASE_URL (verified, 0.158.0), so this writes a
# throwaway CODEX_HOME whose config.toml declares a custom provider. Only the
# Responses API is supported (`wire_api = "chat"` is rejected), which is why
# mock-openai also serves POST /v1/responses.
set -eu
here=$(dirname "$0")
# shellcheck source=lib.sh
. "$here/lib.sh"

need codex
need git
: "${MOCK_OPENAI_URL:?MOCK_OPENAI_URL is not set}"
: "${OPENAI_API_KEY:?OPENAI_API_KEY is not set}"
reach "${MOCK_OPENAI_URL%/v1}"

repo=$(scratch_repo codex)
# Not under /tmp: Codex refuses to create its helper binaries there.
CODEX_HOME=$(mktemp -d "${WORK_DIR:-/work}/codex-home.XXXXXX")
export CODEX_HOME
trap 'rm -rf "$CODEX_HOME"' EXIT
cat > "$CODEX_HOME/config.toml" <<TOML
model = "mock-gpt"
model_provider = "mock"

[model_providers.mock]
name = "Mock OpenAI"
base_url = "${MOCK_OPENAI_URL}"
env_key = "OPENAI_API_KEY"
wire_api = "responses"
TOML

cd "$repo"
say "$(codex --version) in $repo"

# The container is the sandbox: Codex's own bubblewrap sandbox needs user
# namespaces, which a default container does not allow (unverified there).
say "codex exec '$TOOL_PROMPT'"
out=$(timeout 180 codex exec --dangerously-bypass-approvals-and-sandbox "$TOOL_PROMPT" </dev/null 2>&1) || {
  printf '%s\n' "$out" >&2
  die "codex exited non-zero"
}
printf '%s\n' "$out"

check_result "$out" 'hello from mock-openai'
