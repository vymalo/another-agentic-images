# WireMock mocks

Stand-ins for the model providers the baked coding-agent CLIs talk to, run by
[`compose.yaml`](../../compose.yaml) with `wiremock/wiremock:3.13.2`. Each
directory is a WireMock root: `mappings/` (request matching) and `__files/`
(response bodies, including the SSE streams).

| Mock | Compose service, host port | Endpoints | Client |
|---|---|---|---|
| `openai/` | `mock-openai`, `127.0.0.1:8081` | `POST /v1/chat/completions`, `POST /v1/responses`, `GET /v1/models` | OpenCode (chat completions), Codex (responses) |
| `anthropic/` | `mock-anthropic`, `127.0.0.1:8082` | `POST /v1/messages`, `POST /v1/messages/count_tokens`, `GET /v1/models`, `HEAD /api/hello` | Claude Code |

Both answer streaming (`"stream": true`: `text/event-stream`, SSE framing as
the real API, ends with `data: [DONE]` on chat completions and `message_stop`
on Messages) and non-streaming requests.

## Scenario switches

The mock picks its answer from the request. Switches are matched on the raw
request body, so they work through any CLI's prompt, or as a request header
with `curl`.

| To get | Put this in the prompt (body) | Or send this header | Response |
|---|---|---|---|
| Plain text (default) | nothing | | `Hello from mock-openai. This is a canned answer.` (`mock-anthropic` for Messages) |
| A tool call | `[mock:tool-call]` | | `bash` (chat completions), `exec_command` (responses), `Bash` (Messages): `printf 'hello from ...\n' > hello.txt` |
| After the tool ran | (automatic) | | `Done. I created hello.txt.`, whenever the request carries a tool result, so an agent loop ends |
| Rate limit | `[mock:rate-limit]` | `X-Mock-Scenario: rate-limit` | 429 in the provider's error shape, with `Retry-After: 1` |
| Server error | `[mock:server-error]` | `X-Mock-Scenario: server-error` | 500 in the provider's error shape |

Precedence (WireMock `priority`, lower wins): the error switches, then "after
the tool ran" and OpenCode's session-title request (chat completions only; the
two never overlap), then the tool call, then the default text. Both the tool-call
marker and the title request carry the user's prompt, which is why "after the
tool ran" and the title rank above the tool call.

Clients retry 429 and 5xx with backoff, so an error scenario through a CLI can
look like a hang. The compose environment caps Claude Code (`CLAUDE_CODE_MAX_RETRIES=2`);
use `curl` to see the raw error:

```sh
curl -si localhost:8081/v1/chat/completions -H 'Content-Type: application/json' \
  -H 'X-Mock-Scenario: rate-limit' -d '{"model":"mock-gpt","messages":[{"role":"user","content":"hi"}]}'
```

## Editing

`GET localhost:8081/__admin/requests` shows what the CLI actually sent (the
journal keeps 1000 entries), and `POST /__admin/mappings/reset` reloads the
mapping files after an edit, with no restart. The mappings are plain JSON;
SSE bodies in `__files/*.txt` must keep the blank line after every event.

To run a mock without Docker (the jar is the same WireMock version):

```sh
java -jar wiremock-standalone-3.13.2.jar --port 8081 --root-dir dev/wiremock/openai
```

## What is verified

Checked on 2026-09-29 by running the real CLIs of the pinned versions
(OpenCode 1.18.33, Claude Code 2.1.283, Codex 0.158.0) against the standalone
WireMock 3.13.2 jar: a text answer and a tool call that creates `hello.txt` for
each, and the error switches through `curl`. Codex accepts only the Responses
API (`wire_api = "chat"` is rejected at 0.158.0) and ignores `OPENAI_BASE_URL`.
Not verified: the interactive TUIs, and Codex's own sandbox inside a container.
