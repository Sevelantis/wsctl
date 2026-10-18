<div align="center">

<img width="1916" height="821" alt="wsctl — workspace control" src="https://github.com/user-attachments/assets/47621d69-fc98-4d2c-83a3-49761feaf05a" />

One command stands up a complete **Zero-Trust AI Workspace** — in any project, on any OS.

[Quick start](#-quick-start) · [Commands](#-commands) · [What it does](#-what-it-does) · [Requirements](#-requirements)

</div>

---

`wsctl` (workspace control) makes a project's entire development environment portable, reproducible, and
effortless to keep current — all from a single command, anywhere.

---

## 🚀 Quick start

```bash
git clone -b master https://github.com/Sevelantis/wsctl .wsctl && .wsctl/wsctl.sh install
```

Run it from your project's root — from then on, `wsctl <command>` works anywhere in the project.

---

## 🧩 Commands

| Command     | What it does                          |
| ----------- | ------------------------------------- |
| `install`   | Set up the workspace. Safe to re-run. |
| `update`    | Pull the latest.                      |
| `status`    | Show where things stand.              |
| `health`    | Check everything's in place.          |
| `reinstall` | Rebuild clean.                        |
| `reset`     | Tear down, ready to rebuild.          |
| `docker`    | Keep the host's Docker tidy.          |

---

## ✨ What it does

- **Zero-trust by default** — an isolated sandbox with a built-in egress firewall, so AI agents only reach what you allow.
- **Complete setup** — lays the config, tools, and container your project needs to run.
- **Always current** — pull the latest shared setup anytime; never chase versions by hand.
- **Invisible** — fully invisible to git version control; it leaves your project exactly as it found it.
- **Safe to re-run** — run it as often as you like; it never touches your own files.

---

## 📋 Requirements

| Needs              | Why                                                 |
| ------------------ | --------------------------------------------------- |
| **git**            | Clones and updates the workspace.                   |
| **bash or zsh**    | Runs the tool.                                      |
| **Docker**         | Builds and runs the workspace.                      |
| **a GitHub token** | A read-only GitHub PAT to fetch utility submodules. |
