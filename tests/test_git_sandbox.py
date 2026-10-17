"""git sandbox — the tests run real git only inside a throwaway /tmp dir and never touch the user's home or repo."""

import subprocess
import tempfile
from pathlib import Path

SUBMODULES = (".claude", "devcontainers")
TMP = Path(tempfile.gettempdir()).resolve()   # the disposable corner (/tmp); never your repo


def test_git_cannot_climb_out_of_the_sandbox(client, tmp_path):
    """`git rev-parse` in a non-repo dir must fail, proving git cannot climb out to a real repo."""
    loose = tmp_path / "loose_not_a_repo"
    loose.mkdir()
    r = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        cwd=str(loose), env=client.env, text=True, capture_output=True,
    )
    assert r.returncode != 0, f"git escaped the jail and resolved a repo: {r.stdout.strip()!r}"


def test_the_whole_jail_lives_in_the_disposable_tmp_corner(client):
    """HOME, the global config, and the client repo must all live under /tmp, so no real environment is touched."""
    for key in ("HOME", "GIT_CONFIG_GLOBAL"):
        p = Path(client.env[key]).resolve()
        assert str(p).startswith(str(TMP)), f"{key}={p} is not inside the disposable {TMP}"
    assert str(client.path.resolve()).startswith(str(TMP)), "client repo is outside the disposable corner"


def test_global_config_write_stays_in_the_jail(client):
    """A `git config --global` write must land in the sandbox config, never the real ~/.gitconfig."""
    client.git("config", "--global", "wsctl.canary", "sandboxed")
    jailed = Path(client.env["GIT_CONFIG_GLOBAL"])
    # git stores config as INI ([wsctl] / canary = sandboxed), not the dotted key literal
    assert "canary = sandboxed" in jailed.read_text(), "the --global write did not land in the jailed config"


def test_system_config_is_off(client):
    """System-wide git config must be disabled so the host's settings cannot change test results."""
    assert client.env.get("GIT_CONFIG_NOSYSTEM") == "1"
    assert client.env.get("GIT_CONFIG_SYSTEM") == "/dev/null"


def test_each_client_starts_from_a_clean_world(client):
    """A fresh client has no submodule checkouts and only the dummy token, so no state leaks between tests."""
    for sub in SUBMODULES:
        assert not (client.path / sub).exists(), f"{sub} leaked into a fresh client"
    assert "DUMMY" in (client.path / ".env").read_text(), "the client is not using the dummy token"
