"""reinstall — reset then install rebuilds a clean submodule set from messy states, without touching shared files."""

import shutil

from settings import SUBMODULES, DUMMY_FILE, SHARED
TOKEN_VAR = "GH_TOKEN_RO_INFRA"


def _install(client):
    assert client.wsctl("install").returncode == 0, "precondition: install must succeed"


def test_reinstall_delivers_a_clean_workspace(client):
    """After a working install, reinstall must leave both submodules present, with content, on their branch."""
    _install(client)
    r = client.wsctl("reinstall")
    assert r.returncode == 0, f"reinstall failed on a healthy workspace\n{r.stderr}"
    for sub in SUBMODULES:
        f = client.path / sub / DUMMY_FILE[sub]
        assert f.exists() and f.read_text().strip(), f"{sub} not rebuilt clean by reinstall\n{r.stderr}"
        head = client.git("-C", sub, "rev-parse", "--abbrev-ref", "HEAD").stdout.strip()
        assert head == "master", f"{sub} not on its branch after reinstall (on {head!r})"


def test_reinstall_discards_tangled_state_and_rebuilds(client):
    """A submodule with local junk and a detached HEAD must be wiped and re-cloned on its branch."""
    _install(client)
    junk = client.path / ".claude" / "LOCAL_JUNK.txt"
    junk.write_text("stale local state that a clean rebuild must erase\n")
    client.git("-C", ".claude", "checkout", "--detach", "HEAD")
    r = client.wsctl("reinstall")
    assert r.returncode == 0, f"reinstall failed to recover a tangled submodule\n{r.stderr}"
    assert not junk.exists(), "stale junk survived — the reset half did not run"
    assert (client.path / ".claude" / DUMMY_FILE[".claude"]).exists(), ".claude not re-cloned by reinstall"
    head = client.git("-C", ".claude", "rev-parse", "--abbrev-ref", "HEAD").stdout.strip()
    assert head == "master", f".claude still detached after reinstall (on {head!r})"


def test_reinstall_works_from_scratch(client):
    """On a fresh repo reinstall must act like install, not fail with "nothing to reset"."""
    r = client.wsctl("reinstall")
    assert r.returncode == 0, f"reinstall errored from scratch\n{r.stderr}"
    for sub in SUBMODULES:
        assert (client.path / sub / DUMMY_FILE[sub]).exists(), f"{sub} not provisioned by reinstall-from-scratch"


def test_reinstall_preserves_invisibility(client):
    """reinstall must leave the workspace invisible: no .gitmodules, no staged pointer, submodules hidden."""
    _install(client)
    assert client.wsctl("reinstall").returncode == 0
    assert not (client.path / ".gitmodules").exists(), "reinstall created .gitmodules — broke invisibility"
    assert "160000 " not in client.git("ls-files", "--stage").stdout, "reinstall staged a pin — broke invisibility"
    exclude = (client.path / ".git" / "info" / "exclude").read_text()
    for sub in SUBMODULES:
        assert sub in exclude, f"{sub} not hidden after reinstall"


def test_reinstall_never_touches_shared_files(client):
    """Client-owned shared files must survive reinstall unchanged."""
    _install(client)
    markers = {}
    for name in SHARED:
        p = client.path / name
        markers[name] = (p.read_text() if p.exists() else "") + "# client-owned marker\n"
        p.write_text(markers[name])
    assert client.wsctl("reinstall").returncode == 0
    for name in SHARED:
        assert (client.path / name).read_text() == markers[name], f"reinstall altered a shared file: {name}"


def test_reinstall_without_a_token_dies_clearly(client):
    """Without a token reinstall must stop with a message naming the token variable, not a git error."""
    _install(client)
    (client.path / ".env").write_text("# no token here\n")
    r = client.wsctl("reinstall")
    assert r.returncode != 0, "reinstall ran without a token"
    assert TOKEN_VAR in r.stderr, f"the missing-token message should name {TOKEN_VAR}\n{r.stderr}"
