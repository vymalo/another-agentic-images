#!/bin/sh
# Probe both mocks with curl, from the host: one check per endpoint and
# scenario, streaming and not. Exits non-zero on the first mismatch.
#
#   docker compose up -d --wait mock-openai mock-anthropic
#   sh dev/probe-mocks.sh                      # 127.0.0.1:8081 and :8082
#   sh dev/probe-mocks.sh http://127.0.0.1:18081 http://127.0.0.1:18082
#
# Also run by .github/workflows/compose.yml.
set -eu

oa="${1:-http://127.0.0.1:${MOCK_OPENAI_PORT:-8081}}"
an="${2:-http://127.0.0.1:${MOCK_ANTHROPIC_PORT:-8082}}"
json='Content-Type: application/json'
fails=0

# expect <label> <pattern> <curl args...>: the response body must match the grep -E pattern.
expect() {
  label=$1 pattern=$2
  shift 2
  if body=$(curl -fsS --max-time 10 "$@") && printf '%s\n' "$body" | grep -Eq "$pattern"; then
    printf 'ok    %s\n' "$label"
  else
    printf 'FAIL  %s (wanted /%s/)\n%s\n' "$label" "$pattern" "${body:-<no body>}" >&2
    fails=$((fails + 1))
  fi
}

# status <label> <code> <curl args...>: the HTTP status must equal <code> (curl without -f).
status() {
  label=$1 want=$2
  shift 2
  got=$(curl -sS --max-time 10 -o /dev/null -w '%{http_code}' "$@") || got=curl-error
  if [ "$got" = "$want" ]; then
    printf 'ok    %s\n' "$label"
  else
    printf 'FAIL  %s (status %s, wanted %s)\n' "$label" "$got" "$want" >&2
    fails=$((fails + 1))
  fi
}

# ---- mock-openai: chat completions (OpenCode)
chat="$oa/v1/chat/completions"
expect 'openai health'                   '"healthy"'                 "$oa/__admin/health"
expect 'openai models'                   'mock-gpt'                  "$oa/v1/models"
expect 'chat text'                       'Hello from mock-openai'    "$chat" -H "$json" -d '{"model":"m","messages":[{"role":"user","content":"hi"}]}'
expect 'chat text, stream'               '^data: \[DONE\]'           "$chat" -H "$json" -d '{"model":"m","stream":true,"messages":[{"role":"user","content":"hi"}]}'
expect 'chat tool call'                  '"tool_calls"'              "$chat" -H "$json" -d '{"model":"m","messages":[{"role":"user","content":"x [mock:tool-call]"}]}'
expect 'chat tool call, stream'          '"name":"bash"'             "$chat" -H "$json" -d '{"model":"m","stream":true,"messages":[{"role":"user","content":"x [mock:tool-call]"}]}'
expect 'chat after tool result'          'I created hello.txt'       "$chat" -H "$json" -d '{"model":"m","messages":[{"role":"user","content":"x [mock:tool-call]"},{"role":"tool","tool_call_id":"call_mock_1","content":"ok"}]}'
expect 'chat after tool result, stream'  'I created hello.txt'       "$chat" -H "$json" -d '{"model":"m","stream":true,"messages":[{"role":"user","content":"x [mock:tool-call]"},{"role":"tool","tool_call_id":"call_mock_1","content":"ok"}]}'
status 'chat rate limit (header)'        429 "$chat" -H "$json" -H 'X-Mock-Scenario: rate-limit' -d '{"model":"m","messages":[]}'
status 'chat server error (prompt)'      500 "$chat" -H "$json" -d '{"model":"m","messages":[{"role":"user","content":"[mock:server-error]"}]}'

# ---- mock-openai: responses (Codex)
resp="$oa/v1/responses"
expect 'responses text'                  'Hello from mock-openai'    "$resp" -H "$json" -d '{"model":"m","input":"hi"}'
expect 'responses text, stream'          '^event: response.completed' "$resp" -H "$json" -d '{"model":"m","stream":true,"input":"hi"}'
expect 'responses tool call, stream'     '"name":"exec_command"'     "$resp" -H "$json" -d '{"model":"m","stream":true,"input":"x [mock:tool-call]"}'
expect 'responses after tool output'     'I created hello.txt'       "$resp" -H "$json" -d '{"model":"m","input":[{"type":"function_call_output","call_id":"call_mock_1","output":"ok"}]}'
status 'responses rate limit (prompt)'   429 "$resp" -H "$json" -d '{"model":"m","input":"[mock:rate-limit]"}'

# ---- mock-anthropic: messages (Claude Code)
msgs="$an/v1/messages"
expect 'anthropic health'                '"healthy"'                 "$an/__admin/health"
expect 'anthropic models'                'mock-claude'               "$an/v1/models"
expect 'anthropic count_tokens'          '"input_tokens"'            "$an/v1/messages/count_tokens" -H "$json" -d '{"model":"m","messages":[{"role":"user","content":"hi"}]}'
expect 'messages text'                   'Hello from mock-anthropic' "$msgs" -H "$json" -d '{"model":"m","max_tokens":10,"messages":[{"role":"user","content":"hi"}]}'
expect 'messages text, stream'           '^event: message_stop'      "$msgs" -H "$json" -d '{"model":"m","max_tokens":10,"stream":true,"messages":[{"role":"user","content":"hi"}]}'
expect 'messages tool use'               '"type": *"tool_use"'       "$msgs" -H "$json" -d '{"model":"m","max_tokens":10,"messages":[{"role":"user","content":"x [mock:tool-call]"}]}'
expect 'messages tool use, stream'       '"type":"input_json_delta"' "$msgs" -H "$json" -d '{"model":"m","max_tokens":10,"stream":true,"messages":[{"role":"user","content":"x [mock:tool-call]"}]}'
expect 'messages after tool result'      'I created hello.txt'       "$msgs" -H "$json" -d '{"model":"m","max_tokens":10,"messages":[{"role":"user","content":"x [mock:tool-call]"},{"role":"assistant","content":[{"type":"tool_use","id":"toolu_mock_01","name":"Bash","input":{}}]},{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_mock_01","content":"ok"}]}]}'
status 'messages rate limit (header)'    429 "$msgs" -H "$json" -H 'X-Mock-Scenario: rate-limit' -d '{"model":"m","max_tokens":10,"messages":[]}'
status 'messages server error (prompt)'  500 "$msgs" -H "$json" -d '{"model":"m","max_tokens":10,"messages":[{"role":"user","content":"[mock:server-error]"}]}'

if [ "$fails" -gt 0 ]; then
  printf '%s check(s) failed\n' "$fails" >&2
  exit 1
fi
echo 'all mock probes passed'
