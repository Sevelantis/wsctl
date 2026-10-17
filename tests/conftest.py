"""Centralized git-isolated-env lifecycle for the wsctl unit suite.

Each test runs the real `git` + `wsctl.sh` against throwaway repos whose submodule
"remotes" are local bare repos — no network, no real token. A dummy token exercises the
full token wiring; the github-scoped auth header never applies to a local path, so the
pull still succeeds. FAKE values only — never read a real `.env`, never assert on one.
"""

import os
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]  # wsctl/
WSCTL = ROOT / "wsctl.sh"
SUBMODULES = (".claude", "devcontainers")
DUMMY_FILE = {".claude": "abc.txt", "devcontainers": "xyz.txt"}
DUMMY_TOKEN = "github_pat_DUMMY_0000000000000000000000"


def _run(cmd, cwd, env, check=True):
    """Run a command, capture text output, return the CompletedProcess."""
    return subprocess.run(
        cmd, cwd=str(cwd), env=env, text=True, capture_output=True, check=check
    )


def _env(home: Path, remote_base: Path) -> dict:
    """A git env jailed to the sandbox: fails closed, can't bleed into the real repo."""
    e = dict(os.environ)
    e.update(
        HOME=str(home),
        GIT_CONFIG_GLOBAL=str(
            home / ".gitconfig"
        ),  # the jailed global (allows local-file submodules)
        GIT_CONFIG_SYSTEM="/dev/null",
        GIT_CONFIG_NOSYSTEM="1",
        GIT_TERMINAL_PROMPT="0",
        GIT_ASKPASS="/bin/true",
        GIT_CEILING_DIRECTORIES=str(
            home.parent
        ),  # git can't walk up past the sandbox root
        WSCTL_REMOTE_BASE=str(
            remote_base
        ),  # the seam: clone from local bares, not github
    )
    return e


@pytest.fixture(scope="session")
def home(tmp_path_factory) -> Path:
    """A fake HOME whose only git config allows local-file submodules + a committer identity."""
    h = tmp_path_factory.mktemp("home")
    (h / ".gitconfig").write_text(
        "[user]\n\tname = wsctl-test\n\temail = test@wsctl.local\n"
        '[protocol "file"]\n\tallow = always\n'
    )
    return h


@pytest.fixture(scope="session")
def remotes(home, tmp_path_factory) -> Path:
    """Two seeded bare repos standing in for Sevelantis/{.claude,devcontainers}. Returns their base dir."""
    base = tmp_path_factory.mktemp("remotes")
    env = _env(home, base)
    for name in SUBMODULES:
        bare = base / f"{name}.git"
        _run(["git", "init", "-q", "--bare", "-b", "master", str(bare)], base, env)
        work = base / f"{name}.work"
        _run(["git", "clone", "-q", str(bare), str(work)], base, env)
        (work / DUMMY_FILE[name]).write_text(f"{name} content\n")
        _run(["git", "add", "-A"], work, env)
        _run(["git", "commit", "-qm", "seed"], work, env)
        _run(["git", "push", "-q", "origin", "master"], work, env)
    return base


class Client:
    """What a test drives: run wsctl + raw git, both jailed and rooted at a fresh client repo."""

    def __init__(self, path: Path, env: dict):
        self.path = path
        self.env = env

    def wsctl(self, *args, check=False, extra_env=None):
        env = {**self.env, **extra_env} if extra_env else self.env
        return _run(["bash", str(WSCTL), *args], self.path, env, check=check)

    def git(self, *args, check=True):
        return _run(["git", *args], self.path, self.env, check=check)


@pytest.fixture
def client(tmp_path, home, remotes) -> Client:
    """A fresh throwaway client repo with a dummy-token .env, ready to run wsctl against the local remotes."""
    repo = tmp_path / "project"
    repo.mkdir()
    env = _env(home, remotes)
    _run(["git", "init", "-q", "-b", "master", str(repo)], repo, env)
    (repo / ".env").write_text(f"GH_TOKEN_RO_INFRA={DUMMY_TOKEN}\n")
    return Client(repo, env)
