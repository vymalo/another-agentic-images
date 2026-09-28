---
name: change-image
description: Add a tool to, or bump a pinned version in, an another-agentic-images image (agent-canvas/Dockerfile), release it, and roll it out to home-os. Use for any Dockerfile or image-workflow change.
---

# Changing an image

## Procedure

1. **Pin it.** New tools get an `ARG NAME_VERSION=…` near the others, with a
   comment saying where the pin comes from (a consuming repo's pin, or the
   registry's latest on a date). Never `latest`.
2. **Install under `/opt`** (or as a root-owned global into `/usr/local`),
   never into `$HOME` — deployment mounts would hide it.
3. **Nested mount points:** if the deployment will mount below a directory the
   image doesn't have (e.g. `~/.local/share/<tool>`), create the parents as
   `openhands` in the image.
4. **Environment:** anything on `PATH` or needed as env goes in both `ENV` and
   `/etc/profile.d/10-toolchains.sh`. Configure tools in their own config files,
   not `npm_config_*`.
5. **Self-updaters off;** keep npm postinstall scripts (native binaries).
6. **Smoke test:** add the tool to the final `bash -lc` `RUN` (login shell,
   uid 10001). Note `set -e` does not fail on `! cmd` — use explicit `test`/`if`.
7. **Lint:** `docker buildx build --check --platform linux/amd64 -f agent-canvas/Dockerfile agent-canvas`.
8. **PR:** follow the template; **wait for the PR's own `Build agent-canvas`
   run to be green before merging**.
9. **After merge:** the `main` run publishes `1.24.0-<sha7>`. If the package
   path is new, check anonymous pull (CLAUDE.md → *Release flow*).
10. **Roll out:** PR to `WhyThatFunction/home-os` bumping
    `charts/apps/values.yaml` (Application `agent-canvas`, `image.tag`); if the
    tool keeps state, add its directories to the `persistence.mounts` list
    there. After ArgoCD syncs, verify in the pod:
    `kubectl --context admin@netcup exec -n agent-canvas agent-canvas-0 -- bash -lc '<tool> --version'`.
