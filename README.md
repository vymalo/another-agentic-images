# another-agentic-images

Container images for the another-agentic family (another-agentic-platform, another-agentic-system) and for self-hosting [OpenHands](https://github.com/OpenHands/OpenHands) Agent Canvas, with the toolchains already in them.

| Image | What | Base |
|---|---|---|
| [`agent-canvas`](#agent-canvas) | OpenHands Agent Canvas plus the toolchains | upstream `ghcr.io/openhands/agent-canvas` |
| [`workspace`](#workspace) | The same toolchains, no Agent Canvas: the runtime for coder agents, and a [dev container](#use-it-as-a-dev-container) base | `debian:trixie-slim` |

Both run the same install script, [`toolchains/install.sh`](toolchains/install.sh), so they provide identical tools. Build from the repo root: `docker buildx build -f <image>/Dockerfile .`

> Renamed from `vymalo/openhand-images` on 2026-09-28. Images now publish to `ghcr.io/vymalo/another-agentic-images/...`; the old `ghcr.io/vymalo/openhand-images/agent-canvas` package keeps its existing tags but receives no new ones.

## `agent-canvas`

`ghcr.io/vymalo/another-agentic-images/agent-canvas`: upstream `ghcr.io/openhands/agent-canvas` with these added:

| Ecosystem | Baked in |
|---|---|
| Rust | rustup + toolchain `1.98.1` (rustfmt, clippy, rust-src, llvm-tools-preview, `wasm32-unknown-unknown`), `just`, `cargo-nextest`, `cargo-deny`, `sccache` |
| Flutter/Dart | Flutter SDK `3.44.4` (bundles Dart), web artifacts precached |
| Node | upstream Node 24 + corepack shims (pnpm/yarn resolve each project's `packageManager`); pnpm store in `~/.cache/pnpm-store` |
| Coding agents | Claude Code `2.1.283`, Codex `0.158.0` and OpenCode `1.18.33` CLIs (sign in, terminal use; `opencode serve`/`web`/`acp`). The ACP adapters Agent Canvas drives Claude Code and Codex through (`claude-agent-acp`, `codex-acp`, plus `gemini`) come from upstream's `/acp-node`. Self-updaters are disabled — bump via the `ARG`s |
| Browser | [obscura](https://github.com/h4ckf0r0day/obscura) `0.2.4`: a headless browser with its own renderer, for screenshots without Playwright or Chromium: `obscura fetch http://127.0.0.1:3000 --allow-private-network --screenshot shot.png` ([below](#obscura)) |
| Native deps | clang, lld, cmake, pkg-config, protobuf-compiler |

**Why:** the upstream image has no Rust or Flutter, so its agent installs them at run time into `$HOME` on the container filesystem. Every restart then throws them away.

<a id="obscura"></a>**obscura:** `obscura` and `obscura-worker` (which `obscura scrape` needs beside it) in `/opt/obscura/bin`, from the release asset `obscura-x86_64-linux.tar.gz`, pinned by `OBSCURA_VERSION` and `OBSCURA_SHA256`. *Verified 2026-10-09* against [h4ckf0r0day/obscura](https://github.com/h4ckf0r0day/obscura) v0.2.4 (Apache-2.0; its README, `docs/CLI-reference.md` and `.github/workflows/release.yml`) and by running the binary on `debian:trixie-slim`:
- It refuses loopback and private addresses unless run with `--allow-private-network` (or `OBSCURA_ALLOW_PRIVATE_NETWORK=1`); the images set neither.
- Its fonts are compiled in (Liberation Sans, Serif and Mono, DejaVu Sans, Noto Color Emoji), so text renders with no font packages in the image. `obscura serve --font-dir <dir>` loads more.
- It links only glibc (2.35 or later), libm and libgcc_s. The renderer is its own, not Chromium's: upstream says long-tail CSS and font rasterization may differ.
- The release publishes no checksum file, so `OBSCURA_SHA256` is the digest of the downloaded asset.

**Layout contract:**
- Toolchains live under `/opt` (`RUSTUP_HOME=/opt/rustup`, launchers in `/opt/cargo/bin`, `/opt/flutter`), never under `$HOME`, so a deployment can mount persistent volumes over home directories without hiding them.
- `CARGO_HOME` stays at its default `~/.cargo`, so crate caches and `cargo install`ed tools follow wherever the deployment persists it.
- `PATH` is also exported from `/etc/profile.d/10-toolchains.sh`. Debian's `/etc/profile` resets `PATH` for login shells, which is what the agent's terminals are.

**Tags:**
- `<agent-canvas version>-<sha7>`: immutable. Pin this in deployments.
- `<agent-canvas version>` and `latest`: moving.

**Bumping:** edit the `ARG`s at the top of [`agent-canvas/Dockerfile`](agent-canvas/Dockerfile) (and the same shared pins in `workspace/Dockerfile`). The upstream base is pinned by tag *and* digest. Merging to `main` publishes.

Consumed by `WhyThatFunction/home-os` (`charts/apps/values.yaml`, Application `agent-canvas`).

## `workspace`

`ghcr.io/vymalo/another-agentic-images/workspace`: the toolchains of `agent-canvas` on a bare `debian:trixie-slim` (pinned by tag and digest), without OpenHands Agent Canvas. It is the runtime image for the adam-rs coder agent, and it is much smaller.

| Ecosystem | Baked in |
|---|---|
| Rust, Flutter/Dart, coding agents, browser, native deps | Exactly the `agent-canvas` set above (the Rust, Flutter, CLI and obscura pins must match, and CI checks it) |
| Node | Node `24.21.0` from nodejs.org (pinned by version and sha256, in `/usr/local`) + corepack shims; pnpm store in `~/.cache/pnpm-store` |
| Base | git, openssh-client, ca-certificates, gcc/g++/make, libssl-dev, tini |

- User `agent` (uid/gid 10001), home `/home/agent`; `/work` is owned by it, for mirrors and worktrees. `/work/workspaces` and `/workspaces` exist too, also owned by it: they are the parents of mount targets (see [Use it as a dev container](#use-it-as-a-dev-container)), and a container runtime would otherwise create them as root.
- `ENTRYPOINT ["tini", "--"]` and no default process: the coder image adds its binary.
- Not included: the ACP adapters (`claude-agent-acp`, `codex-acp`), which `agent-canvas` gets from upstream, and Python.
- Same layout contract as `agent-canvas`, with `/home/agent` in place of `/home/openhands`.

**Tags:**
- `<rust toolchain>-<sha7>`, e.g. `1.98.1-<sha7>`: immutable. Pin this in deployments.
- `latest`: moving. There is no moving `<rust toolchain>` tag, because a Flutter or CLI bump would move it silently.

**Bumping:** edit the `ARG`s at the top of [`workspace/Dockerfile`](workspace/Dockerfile), and the same pins in `agent-canvas/Dockerfile`. New tools go in `toolchains/install.sh` and in both smoke tests. Merging to `main` publishes.

### Use it as a dev container

The image carries a [`devcontainer.metadata` label](https://containers.dev/implementors/spec/#image-metadata) (`remoteUser` and `containerUser` `agent`, `updateRemoteUserUID` `true`), so a repository only has to name it. In `.devcontainer/devcontainer.json`:

```jsonc
{
  "name": "my-project",
  // Pin the immutable <rust toolchain>-<sha7> tag, not latest.
  "image": "ghcr.io/vymalo/another-agentic-images/workspace:1.98.1-<sha7>"
}
```

A tool that implements the [containers.dev](https://containers.dev) spec (the reference [`devcontainer` CLI](https://github.com/devcontainers/cli), for one) then starts the container, runs everything as `agent` in a login shell with the toolchains on `PATH`, and mounts the project folder at `/workspaces/<folder name>`. Try it from a checkout of a project that has that file:

```sh
npx --yes @devcontainers/cli@0.89.0 up --workspace-folder .
npx --yes @devcontainers/cli@0.89.0 exec --workspace-folder . bash -lc 'whoami; rustc --version'
```

- **Tags.** Only images published from the change that added the label carry it; `1.98.1-bc97d51` and older do not. Check an image with `docker inspect --format '{{ index .Config.Labels "devcontainer.metadata" }}' <image>`.
- **`workspaceFolder` is not set by the image.** The spec does not allow it in image metadata (only the properties marked in its [reference](https://containers.dev/implementors/json_reference/) can be), so a repository that wants another folder sets `workspaceFolder` and `workspaceMount` in its own `devcontainer.json`.
- **The entrypoint.** `tini` is the image's `ENTRYPOINT`, but for an image config the spec's `overrideCommand` defaults to `true`: the tool replaces the entrypoint with a sleep loop. Add `"init": true` if the container needs an init process.
- **User ids.** `updateRemoteUserUID` is the spec's default. On a Linux host whose user is not uid 10001, the tool gives `agent` the host user's uid and gid, so files made in the bind-mounted folder belong to you; it changes the ownership of `/home/agent` only. `/work`, `/workspaces` and the toolchains in `/opt` (`/opt/rustup`, `/opt/cargo`, `/opt/flutter`) keep their owner, uid 10001, so `agent` can no longer write to them (`rustup toolchain install`, Flutter's first-run cache). Set `"updateRemoteUserUID": false` in the repository's `devcontainer.json` to keep uid 10001; the mounted folder must then be writable by uid 10001.
- **Size.** The image is large (the toolchains of [`workspace`](#workspace)), and amd64 only. A repository that needs one tool can use a smaller image of its own.
- **Who uses it.** Planned: the default dev container of the adam-rs coder (`vymalo/another-adam-rs`) for a repository that has no `devcontainer.json`. `/work/workspaces` is the parent of the coder's per-run workspace folders, which a dev container binds at the same path.

`tools/check-devcontainer.sh <image>` proves the above against a built image: the CLI merges the label, `up` succeeds, and in a login shell `whoami` is `agent`, `rustc`, `cargo`, `node`, `git` and `opencode` run, `/work/workspaces` and `/workspaces` belong to uid 10001, and a file made in the mounted folder belongs to the host user. `workspace.yml` runs it after every build (needs `docker`, `node`, `jq`; with the setup-buildx builder, `BUILDX_BUILDER=default`, see the script).

## Local testing

[`compose.yaml`](compose.yaml) runs the images next to WireMock stand-ins for the model providers, so the baked CLIs (OpenCode, Claude Code, Codex) work with no API key, no network and no cost. It is for trying an image or a change, and for the "agent edits a repo" loop; it does not replace the image builds.

```sh
docker compose up -d                                   # mocks + the pinned workspace image
docker compose exec workspace bash -l                  # a login shell in it, as uid 10001
docker compose run --rm workspace sh /dev-scripts/try-opencode.sh   # or try-claude.sh, try-codex.sh
sh dev/probe-mocks.sh                                  # curl every mock endpoint and scenario, from the host
docker compose down -v                                 # stop and drop the volumes
```

| Service | Profile | What |
|---|---|---|
| `mock-openai` | (default) | OpenAI-compatible: `POST /v1/chat/completions` (OpenCode), `POST /v1/responses` (Codex), `GET /v1/models`; on `127.0.0.1:8081` |
| `mock-anthropic` | (default) | Anthropic Messages API: `POST /v1/messages`, `count_tokens`, `GET /v1/models` (Claude Code); on `127.0.0.1:8082` |
| `workspace` | (default) | The published image, pinned to `1.98.1-bc97d51` by tag and digest; `sleep infinity`, volume `work` on `/work` |
| `workspace-build` | `build` | The same image built from [`workspace/Dockerfile`](workspace/Dockerfile) with the repo root as context: `docker compose --profile build up -d --build workspace-build`. `GITHUB_TOKEN_FILE=<file>` supplies the optional `github_token` build secret |
| `agent-canvas` | `agent-canvas` | The published image (multi-GB), pinned by tag and digest: UI at <http://localhost:8000/canvas> |

Only the mocks: `docker compose up -d --wait mock-openai mock-anthropic`. Host ports come from `MOCK_OPENAI_PORT`, `MOCK_ANTHROPIC_PORT` and `AGENT_CANVAS_PORT`; all bind to `127.0.0.1`.

**Wiring.** The services carry the environment that points each CLI at its mock, with dummy keys:

| CLI | How it reaches the mock | Notes |
|---|---|---|
| OpenCode | `OPENCODE_CONFIG_CONTENT`: a custom `@ai-sdk/openai-compatible` provider, `baseURL` `http://mock-openai:8080/v1` | `OPENCODE_DISABLE_MODELS_FETCH=true` keeps it off models.dev. Verified |
| Claude Code | `ANTHROPIC_BASE_URL=http://mock-anthropic:8080`, `ANTHROPIC_API_KEY` (dummy), `ANTHROPIC_MODEL=sonnet` | Verified in print mode (`claude -p`). The interactive TUI asks once to approve a custom API key (unverified) |
| Codex | A `[model_providers.*]` entry with `wire_api = "responses"` in its `config.toml`; `dev/try-codex.sh` writes one | `OPENAI_BASE_URL` is ignored, and `wire_api = "chat"` is rejected (verified, 0.158.0) |

To use Codex by hand, in the container: put the block below in `$CODEX_HOME/config.toml` (with a `CODEX_HOME` outside `~`, or in a scratch directory) and run `codex exec --dangerously-bypass-approvals-and-sandbox "..."`.

```toml
model = "mock-gpt"
model_provider = "mock"
[model_providers.mock]
name = "Mock OpenAI"
base_url = "http://mock-openai:8080/v1"
env_key = "OPENAI_API_KEY"
wire_api = "responses"
```

**Scenarios.** The mocks answer plain text by default. A prompt containing `[mock:tool-call]` gets a tool call that writes `hello.txt` (then the final text once the tool result comes back), which is what the `dev/try-*.sh` scripts use. `[mock:rate-limit]` and `[mock:server-error]` (or the header `X-Mock-Scenario: rate-limit|server-error`) return the provider's 429 and 500 error bodies. Streaming and non-streaming requests are both served. Details, precedence and what was verified against the real CLIs: [`dev/wiremock/README.md`](dev/wiremock/README.md).

`.github/workflows/compose.yml` runs `docker compose config`, starts the mocks, curls them and runs the three `try-*.sh` scripts in the pinned workspace image, whenever `compose.yaml` or `dev/` change. To try newer tools, bump the pinned `workspace` / `agent-canvas` tag and digest in `compose.yaml` (both tags are immutable).
