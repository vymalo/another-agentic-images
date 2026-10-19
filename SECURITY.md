# Security policy

## Report a vulnerability privately

Use GitHub's private vulnerability reporting: open the repository's **Security** tab and choose
**Report a vulnerability**, or go to
<https://github.com/vymalo/another-agentic-images/security/advisories/new>.

**Do not open a public issue, a pull request or a discussion for a vulnerability.** A public report gives everyone the
details before there is a fix.

## What to include

- What is affected: the image (`workspace` or `agent-canvas`), its tag, and the file or layer.
- What an attacker can do, and what they need first (a process in the container, a mounted volume).
- Steps to reproduce, or a proof of concept. Building the image and running it locally is enough; see "Local testing"
  in [`README.md`](README.md).
- Anything you already know about a fix.

Please reproduce against your own machine. Do not test against a deployment you do not own.

## Scope

In scope: what this repository builds and how it builds it. Of particular interest: a secret left in an image layer, a
download that is not pinned and verified, a file or directory that gives a process more access than the layout contract in
[`CLAUDE.md`](CLAUDE.md) says, and a way the images run as root where they should not. A vulnerability in a tool we bake
in (Rust, Node, a coding-agent CLI, the obscura browser) or in a base image is best reported to that project; tell us
too if our pin or our configuration makes it worse.

## Known limitations need no report

Some limits are already written down. Reporting them privately adds nothing; a fix or a better idea is welcome as an
ordinary issue or pull request.

- The shared package cache at `/cache` is **one trust domain**: every run that mounts it trusts everything on it.
  It is described in [`README.md`](README.md#package-caches). The effect on isolation between people is
  [adam ADR 0041, "Known limits, not built"](https://github.com/vymalo/another-adam-rs/blob/main/docs/decisions/0041-a-run-pod-sees-only-its-own-run.md#known-limits-not-built).
- The hardening work on the [product roadmap](https://github.com/vymalo/another-agentic-system/blob/main/ROADMAP.md):
  the tickets labelled `security`.

## Supported versions

Fixes ship as a new image tag built from `main`. A published immutable tag is not patched, so move your pin to the new
tag.
