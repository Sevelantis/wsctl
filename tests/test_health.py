"""health — the read-only drift check reports missing, detached, or un-hidden submodules and never fixes them."""

import shutil

from settings import SUBMODULES


def _install(client):
    assert client.wsctl("install").returncode == 0, "precondition: install must succeed"


def test_health_green_on_a_fresh_install(client):
    """A fresh install must pass health, or every other health failure would be meaningless."""
    _install(client)
    r = client.wsctl("health")
    assert r.returncode == 0, f"health flagged a clean install\n{r.stderr}"


def test_health_flags_a_missing_submodule(client):
    """A deleted submodule must make health fail and name it, or the client believes the workspace is fine."""
    _install(client)
    shutil.rmtree(client.path / ".claude")
    r = client.wsctl("health")
    assert r.returncode != 0, "health passed with a submodule missing"
    assert ".claude" in r.stderr, f"health didn't name the missing submodule\n{r.stderr}"


def test_health_flags_a_detached_submodule(client):
    """A detached submodule cannot be pulled; health must flag it before `update` fails."""
    _install(client)
    client.git("-C", ".claude", "checkout", "--detach", "HEAD")
    r = client.wsctl("health")
    assert r.returncode != 0, "health passed with a detached submodule"
    assert "detached" in r.stderr.lower(), f"no clear detached diagnostic\n{r.stderr}"


def test_health_flags_a_lost_hide(client):
    """If `.git/info/exclude` loses its entries, health must say so, or the submodules appear in `git status`."""
    _install(client)
    (client.path / ".git" / "info" / "exclude").write_text("")  # wipe the hide
    r = client.wsctl("health")
    assert r.returncode != 0, "health passed with the hide-exclude gone"
    assert "exclude" in r.stderr.lower() or "hidden" in r.stderr.lower(), f"no clear un-hidden diagnostic\n{r.stderr}"


def test_health_is_read_only(client):
    """health must run without a token and must not re-create a missing submodule; it only reports."""
    _install(client)
    shutil.rmtree(client.path / ".claude")
    (client.path / ".env").write_text("# no token\n")
    client.wsctl("health")
    assert not (client.path / ".claude").exists(), "health re-created a submodule — it must be read-only"


def test_health_lists_each_component_checked(client):
    """health must print one line per check (each submodule and the hide), so users can see what was verified."""
    _install(client)
    r = client.wsctl("health")
    assert r.returncode == 0, r.stderr
    for sub in SUBMODULES:
        assert sub in r.stderr, f"health didn't show a line for {sub}\n{r.stderr}"
    assert "hidden" in r.stderr.lower(), f"health didn't show the hide check\n{r.stderr}"
