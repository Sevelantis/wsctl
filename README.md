# wsctl

**Stand up a complete, sandboxed AI devcontainer with one command — in any project, on any OS.**

`wsctl` (workspace control) is a CLI that provisions and manages a ready-to-use AI Sandbox Devcontainer. It
brings a project to a known-good state with a single command and keeps it current, authenticating with a
read-only GitHub token scoped to two private repositories.

## Install

```bash
git clone -b master https://github.com/Sevelantis/wsctl .wsctl && .wsctl/wsctl.sh install
```

Run it from your project's root directory. Requires only `git` and `bash`/`zsh` (plus Docker to run the
devcontainer itself).

## Features

- **Lifecycle CLI, not a one-shot installer** — one tool manages the workspace from first install through every
  update, reset, and health check.
- **One-command onboarding** — drop the platform into any project, on any OS with basic developer tooling
  (`git`, `bash`/`zsh`).
- **Fully scripted setup** — Bash automates the entire provisioning; you paste a single line.
- **Invisible Mode** — the platform's repositories stay completely invisible in your project's remote, managed
  through local `.git` state (never surfaced — not even in `.gitignore`).
- **Verb-driven interface** — `install`, `update`, `reset`, `reinstall`, `health`, and `configure`, with a
  single `wsctl.toml` as the source of truth for workspace state.
- **Docker hygiene** — `wsctl docker-clean` and `wsctl docker-audit` reclaim Docker build-cache before it fills
  the host disk.

### Roadmap

- **MCP Builder** — compose a custom combination of MCP servers for your setup. Not yet available; the
  underlying stack is ready.
