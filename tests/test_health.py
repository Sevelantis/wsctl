"""health — the read-only drift diagnosis (no token, no network).

`health` is what tells a client whether their invisible workspace has drifted from target, before they
reach for `reinstall`. Each test names the real breakage it must catch. health must NEVER heal or clone —
read-only is the contract; a health that silently fixed things would hide the very drift it reports.
Invisible mode is the only mode, so `install` (no flag) yields the invisible on-disk state these check.
"""

import shutil

SUBMODULES = (".claude", "devcontainers")


def _install(client):
    assert client.wsctl("install").returncode == 0, "precondition: install must succeed"


def test_health_green_on_a_fresh_install(client):
    """A just-installed workspace is at target: health exits 0 and says so. If this is ever red, every
    other health assertion is meaningless (it would cry drift on a perfect setup)."""
    _install(client)
    r = client.wsctl("health")
    assert r.returncode == 0, f"health flagged a clean install\n{r.stderr}"


def test_health_flags_a_missing_submodule(client):
    """A managed folder vanished (deleted, or a fresh clone before `install`): health must report it
    non-zero so the client knows to heal, never pretend the workspace is fine."""
    _install(client)
    shutil.rmtree(client.path / ".claude")
    r = client.wsctl("health")
    assert r.returncode != 0, "health passed with a submodule missing"
    assert ".claude" in r.stderr, f"health didn't name the missing submodule\n{r.stderr}"


def test_health_flags_a_detached_submodule(client):
    """A detached checkout has no branch to fast-forward; health must catch it before `update` silently
    can't pull — the exact state that made the old tool look broken."""
    _install(client)
    client.git("-C", ".claude", "checkout", "--detach", "HEAD")
    r = client.wsctl("health")
    assert r.returncode != 0, "health passed with a detached submodule"
    assert "detached" in r.stderr.lower(), f"no clear detached diagnostic\n{r.stderr}"


def test_health_flags_a_lost_hide(client):
    """`.git/info/exclude` lost its entries (it never travels, so a fresh clone starts un-hidden). health
    must report it — otherwise the client unknowingly leaks both submodules into their `git status`."""
    _install(client)
    (client.path / ".git" / "info" / "exclude").write_text("")  # wipe the hide
    r = client.wsctl("health")
    assert r.returncode != 0, "health passed with the hide-exclude gone"
    assert "exclude" in r.stderr.lower() or "hidden" in r.stderr.lower(), f"no clear un-hidden diagnostic\n{r.stderr}"


def test_health_is_read_only(client):
    """The contract: health never heals and needs no key. With a submodule missing AND no token in .env,
    health must still run, report, and NOT re-create anything — a diagnosis, not a silent fix."""
    _install(client)
    shutil.rmtree(client.path / ".claude")
    (client.path / ".env").write_text("# no token\n")
    client.wsctl("health")
    assert not (client.path / ".claude").exists(), "health re-created a submodule — it must be read-only"
