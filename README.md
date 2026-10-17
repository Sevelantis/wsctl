<div align="center">

<img width="1916" height="821" alt="image" src="https://github.com/user-attachments/assets/47621d69-fc98-4d2c-83a3-49761feaf05a" />

**One command stands up a complete, sandboxed AI devcontainer — in any project, on any OS.**

![tests](https://img.shields.io/badge/tests-passing-2ea44f?style=flat-square)
![bash](https://img.shields.io/badge/pure_bash-0_dependencies-1a1a2e?style=flat-square)

[Quick start](#-quick-start) · [Commands](#-commands) · [What it does](#-what-it-does) · [Requirements](#-requirements)

</div>

---

`wsctl` (workspace control) brings any project to a known-good state with a single command, keeps the platform
current on demand, and authenticates with a read-only GitHub token scoped to two private repositories. It
commits nothing to your project and never prompts for secrets.

<!-- Install cast goes here once captured — drop the file at assets/wsctl-install.svg and uncomment:
<div align="center">
  <img src="assets/wsctl-install.svg" alt="wsctl install, running" width="760">
</div>
-->

---

## 🚀 Quick start

```bash
git clone -b master https://github.com/Sevelantis/wsctl .wsctl && .wsctl/wsctl.sh install
```

Run it from your project's root. Add your read-only token to `.env` by hand first — `wsctl` never prompts for
it. `install` adds a `wsctl` command to your shell: open a new terminal (or `source` your rc), then run
`wsctl <command>` from anywhere in the project.

---

## 🧩 Commands

| Command     | What it does                                                                |
| ----------- | --------------------------------------------------------------------------- |
| `install`   | Lay config from templates and clone both managed repos, hidden. Idempotent. |
| `update`    | Fast-forward both managed repos on their current branch.                    |
| `status`    | Show each repo's branch and dirty state. Read-only — no network, no token.  |
| `health`    | Report drift (missing / detached / un-hidden), one line per check.          |
| `reinstall` | Reset, then install — rebuild a clean set. Your own files stay untouched.   |
| `reset`     | Clear the managed repos' local git state so `install` can rebuild.          |
| `docker`    | Host Docker hygiene: `wsctl docker audit` · `wsctl docker clean`.           |

---

## ✨ What it does

- **Invisible** — nothing it adds shows in your `git status`: no committed pins, no `.gitmodules`, nothing pushed.
- **Read-only** — a read-only token scoped to two repositories, injected per command, never written to disk.
- **Current on demand** — `update` fast-forwards the platform to the latest, so you never chase versions by hand.

---

## 📋 Requirements

| Needs           | Why                                                                                    |
| --------------- | -------------------------------------------------------------------------------------- |
| **git**         | Clone the platform and keep it current.                                                |
| **bash or zsh** | The tool runs in Bash; `install` adds the `wsctl` command to your shell.               |
| **Docker**      | Build and run the devcontainer itself.                                                 |

> Another shell still works — run `bash .wsctl/wsctl.sh <command>` directly.

---

## 🗺️ Roadmap

- **`configure` + `wsctl.toml`** — persisted per-project settings (name, port, and more) you can edit later.
- **MCP Builder** — compose a custom set of MCP servers for your setup.
