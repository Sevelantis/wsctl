# wsctl

> **One command stands up a complete, sandboxed AI devcontainer — in any project, on any OS.**

`wsctl` (workspace control) provisions and manages a ready-to-use AI devcontainer. It brings a project to a
known-good state with a single command, keeps the platform current on demand, and authenticates with a
read-only GitHub token scoped to two private repositories.

## Quick start

```bash
git clone -b master https://github.com/Sevelantis/wsctl .wsctl && .wsctl/wsctl.sh install
```

Run it from your project's root. You need only `git` and `bash`/`zsh` (plus Docker to run the devcontainer
itself). Add your read-only token to `.env` by hand before running — `wsctl` never prompts for it.

## Commands

| Command     | What it does                                                                  |
| ----------- | ----------------------------------------------------------------------------- |
| `install`   | Lay config from templates and clone both managed repos (hidden). Idempotent.  |
| `update`    | Fast-forward both managed repos on their current branch.                      |
| `status`    | Show each repo's branch and dirty state. Read-only; no network, no token.     |
| `health`    | Report drift (missing / detached / un-hidden), one line per check. Read-only. |
| `reinstall` | Reset, then install — rebuild a clean set. Leaves your own files untouched.   |
| `reset`     | Clear the managed repos' local git state so `install` can rebuild.            |
| `docker`    | Host Docker hygiene: `wsctl docker audit` / `wsctl docker clean`.             |

## Features

- **Lifecycle manager, not a one-shot installer** — one tool from first install through every update, health
  check, and rebuild.
- **One-command onboarding** — paste a single line; Bash does the rest, on any OS with `git` and `bash`/`zsh`.
- **Invisible** — nothing the platform adds shows in your `git status`: not the managed repos, not `wsctl`
  itself. They live as plain clones hidden by local `.git` state — no committed pins, no `.gitmodules`, nothing
  in `.gitignore`, nothing pushed.
- **Stays current** — `update` fast-forwards the managed platform to the latest on demand, so you never chase
  versions by hand.
- **Read-only by design** — authenticates with a read-only token scoped to two repositories, injected per
  command and never written to disk.
- **Docker hygiene** — `wsctl docker` reclaims build-cache before it fills the host disk.

## Roadmap

- **`wsctl` command** — after install, run `wsctl <command>` from anywhere in your project instead of
  `.wsctl/wsctl.sh`. Designed; building next.
- **`configure` + `wsctl.toml`** — persisted per-project settings (name, port, and more) you can edit after
  onboarding. Planned.
- **MCP Builder** — compose a custom set of MCP servers for your setup. Planned.
