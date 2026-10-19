# Contributing to another-agentic-images

Thank you for helping. This repository builds the **container images** of the another-agentic family, with the
toolchains baked in: `workspace` (the runtime of the coder agent, and a dev container base) and `agent-canvas`
(OpenHands Agent Canvas plus the same toolchains). It is one of four repositories. The product roadmap, with every open
piece of work as a GitHub issue, is in
[`ROADMAP.md` of another-agentic-system](https://github.com/vymalo/another-agentic-system/blob/main/ROADMAP.md).
The work that belongs here today is
[Move GitHub Actions off Node 20](https://github.com/vymalo/another-agentic-images/issues/13), a `good first issue`.

## Find something to work on

1. Pick an issue from the roadmap: a `good first issue`, a `help wanted` ticket, or any ticket whose "Who and when"
   says anyone.
2. **Claim it** by commenting on the issue. If you stop, say so.
3. On a large ticket, or any change to a toolchain pin, **agree the approach in the issue** before you write code.

## Set up, build and test

You need Docker with Buildx and Compose v2, `shellcheck`, and `curl`. The images are `linux/amd64` and large (several
GB), so a full build takes a while and needs disk. Both builds use the **repository root** as the context.

```sh
git config core.hooksPath .githooks                                               # once per clone
docker buildx build --check --platform linux/amd64 -f agent-canvas/Dockerfile .   # lint (repo root is the context)
docker buildx build --check --platform linux/amd64 -f workspace/Dockerfile .      # lint
sh -n toolchains/install.sh && sh tools/check-pins.sh                             # syntax; shared pins equal
shellcheck tools/check-devcontainer.sh                                            # clean
docker compose --profile '*' config -q && shellcheck dev/*.sh                     # compose.yaml valid for every profile; dev scripts clean
docker compose up -d --wait mock-openai mock-anthropic                            # the mocks (README.md "Local testing")
sh tools/check-devcontainer.sh <image>                                            # the devcontainer CLI can use a built workspace image
```

To build an image, run `docker buildx build -f workspace/Dockerfile -t workspace:dev .`. The **last `RUN` of each
Dockerfile is the smoke test**, in a login shell as the runtime user, so a build that succeeds has run it. CI does the
same: [`workspace.yml`](.github/workflows/workspace.yml), [`agent-canvas.yml`](.github/workflows/agent-canvas.yml) and
[`compose.yml`](.github/workflows/compose.yml). "Local testing" in [`README.md`](README.md) shows how to try the baked
CLIs against the mocks.

## Conventions

- **Conventional Commits**, enforced by `tools/commit-lint.sh` in the local hook and in CI. Shape:
  `<type>[(scope)][!]: <description>`. Types: `feat fix docs style refactor perf test build ci chore revert`. The pull
  request title is validated too.
- **One recipe.** `toolchains/install.sh` is the only place that installs toolchains, and both Dockerfiles run it. A
  tool change goes in the script **and** in both Dockerfiles' version `ARG`s and smoke tests. `tools/check-pins.sh`
  fails when the shared pins differ.
- **The layout contract** in [`CLAUDE.md`](CLAUDE.md) holds for every change. In short: toolchains live under `/opt`,
  never under `$HOME`; the parents of nested mount points are created as the runtime user; `PATH` is set in
  `/etc/profile.d` as well as `ENV`; each tool is configured in its own config file; self-updaters are off; package
  caches live under `/cache`. The `change-image` skill in `.agents/skills/` walks through a change.
- **Pin by tag and digest.** A base image is pinned by tag *and* digest, a downloaded release by version and sha256. A
  new package path must be checked for anonymous pull before a deployment points at it.
- **Mark facts** about third parties as *verified* (date and source) or *unverified*.
- **Docs.** This repository has no ADRs: its rules are in `README.md` and `CLAUDE.md`. Update `README.md` in the same
  pull request as a change to what an image contains, its tags, or the local testing setup.
- **Mocks must match the real clients.** Check a mapping change with the real CLIs at the versions in the Dockerfiles,
  not only with `curl`.

## Open a pull request

1. Work on a branch and open a pull request against `main`. Keep it to one concern.
2. Give it a Conventional Commit title.
3. Fill in [`.github/PULL_REQUEST_TEMPLATE.md`](.github/PULL_REQUEST_TEMPLATE.md), the AI-governance template: Summary
   (with a link to the source of truth, such as the issue), Intent, Scope, Verification (the commands you ran and their
   results), Screenshots or evidence, Risk, AI Usage Declaration and Reviewer Focus. The `AI Governance` check fails if
   the body is missing them.
4. These checks must pass: `AI Governance` and `Commit Lint`, `Build agent-canvas` and `Build workspace` when an image
   or `toolchains/` changes, and `Compose` when `compose.yaml` or `dev/` changes.
5. A maintainer merges the pull request when CI is green. A pull request's own image build must be green first (both
   builds when `toolchains/` changes): the smoke test is the only proof that the tools work as the runtime user.
   Merging to `main` publishes the image.

## AI-assisted contributions

They are welcome, and you declare them in the *AI Usage Declaration* of the pull request: what the AI did, and that you
read, understand and accept responsibility for every change. AI output is not evidence: run the checks yourself. The
rules are in the [AI governance](https://adorsys-gis.github.io/ai-governance/) guide this repository follows. If you use
a coding agent, point it at [`CLAUDE.md`](CLAUDE.md) (`AGENTS.md` is a link to it).

## Security

Do not report a vulnerability in a public issue. See [`SECURITY.md`](SECURITY.md).

## Licence

This repository is licensed under the [MIT licence](LICENSE). A contribution you submit is licensed the same way.
