"""git sandbox — proof the test sandbox is disposable, fenced, and never touches the real env.

Model A (chosen 2026-10-09): we test the REAL git binary via subprocess, so OS-level
"no-access" jailing isn't available here (unprivileged namespaces are blocked). Instead we
guarantee: every git call runs in a throwaway /tmp dir, fenced by GIT_CEILING_DIRECTORIES so
git can't climb out to the real repo, with HOME + global config redirected into that same
disposable corner. These tests prove all of it POSITIVELY — never reading or mutating your
real home or repo. A silent jail-leak would make every other green test a lie (the old
hand-rolled bash jail was once proven a no-op).
"""

import subprocess
import tempfile
from pathlib import Path

SUBMODULES = (".claude", "devcontainers")
TMP = Path(tempfile.gettempdir()).resolve()   # the disposable corner (/tmp); never your repo


def test_git_cannot_climb_out_of_the_sandbox(client, tmp_path):
    """THE load-bearing guard: from a non-repo dir inside the jail, `git rev-parse` must FAIL.
    GIT_CEILING_DIRECTORIES stops git walking up to discover any outer (real) repo."""
    loose = tmp_path / "loose_not_a_repo"
    loose.mkdir()
    r = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        cwd=str(loose), env=client.env, text=True, capture_output=True,
    )
    assert r.returncode != 0, f"git escaped the jail and resolved a repo: {r.stdout.strip()!r}"


def test_the_whole_jail_lives_in_the_disposable_tmp_corner(client):
    """Positive containment (no real-env reference): HOME, the global-config file, and the
    client repo all live under /tmp — the throwaway corner pytest auto-deletes — so nothing
    the tests touch is your real environment."""
    for key in ("HOME", "GIT_CONFIG_GLOBAL"):
        p = Path(client.env[key]).resolve()
        assert str(p).startswith(str(TMP)), f"{key}={p} is not inside the disposable {TMP}"
    assert str(client.path.resolve()).startswith(str(TMP)), "client repo is outside the disposable corner"


def test_global_config_write_stays_in_the_jail(client):
    """A `git config --global` write lands in the jailed file (which lives in /tmp, per the test
    above) — proving it cannot reach your real ~/.gitconfig. No real-home read needed."""
    client.git("config", "--global", "wsctl.canary", "sandboxed")
    jailed = Path(client.env["GIT_CONFIG_GLOBAL"])
    # git stores config as INI ([wsctl] / canary = sandboxed), not the dotted key literal
    assert "canary = sandboxed" in jailed.read_text(), "the --global write did not land in the jailed config"


def test_system_config_is_off(client):
    """No machine-wide config is read: GIT_CONFIG_NOSYSTEM=1 + GIT_CONFIG_SYSTEM=/dev/null."""
    assert client.env.get("GIT_CONFIG_NOSYSTEM") == "1"
    assert client.env.get("GIT_CONFIG_SYSTEM") == "/dev/null"


def test_each_client_starts_from_a_clean_world(client):
    """Volatility: a fresh client carries no submodule checkouts and only the dummy token —
    no state bleeds in from another test or from the real repo."""
    for sub in SUBMODULES:
        assert not (client.path / sub).exists(), f"{sub} leaked into a fresh client"
    assert "DUMMY" in (client.path / ".env").read_text(), "the client is not using the dummy token"
