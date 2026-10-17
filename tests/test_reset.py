"""reset — clean the submodules' local git-state so `install` can rebuild (UC-7).

The heavy inverse of provisioning: remove the two managed submodule folders + their internal git
state + any staged pin + the invisible exclude, so a fresh `install` rebuilds from scratch. It must
be surgical — NEVER touch the client's co-owned shared files (.env/.mcp.json/.npmrc/compose) — and
idempotent. `reset` + `install` is also the basis of the `reinstall` verb (reset-then-install).
"""

SUBMODULES = (".claude", "devcontainers")
DUMMY_FILE = {".claude": "abc.txt", "devcontainers": "xyz.txt"}
SHARED = (".mcp.json", ".npmrc", "docker-compose.client.yaml", ".env")


def test_reset_removes_the_submodule_folders(client):
    """reset clears the platform folders so install can re-provision them."""
    assert client.wsctl("install").returncode == 0
    assert client.wsctl("reset").returncode == 0, "reset failed"
    for sub in SUBMODULES:
        assert not (client.path / sub).exists(), f"{sub} folder survived reset"


def test_reset_removes_internal_git_modules(client):
    """The usual breakage lives in .git/modules/<name> (stale state + leftover locks) — reset must clear it."""
    assert client.wsctl("install").returncode == 0
    client.wsctl("reset")
    for sub in SUBMODULES:
        assert not (client.path / ".git" / "modules" / sub).exists(), f".git/modules/{sub} survived reset"


def test_reset_never_touches_shared_files(client):
    """The firm boundary (UC-7): reset cleans platform git-state ONLY; the client's co-owned files are off-limits."""
    assert client.wsctl("install").returncode == 0
    assert client.wsctl("reset").returncode == 0  # not vacuous: reset must have run
    for name in SHARED:
        assert (client.path / name).exists(), f"reset destroyed a shared file: {name}"


def test_reset_is_idempotent_on_a_clean_repo(client):
    """reset on a repo with nothing provisioned must be a harmless no-op, never an error."""
    r = client.wsctl("reset")
    assert r.returncode == 0, f"reset errored on a clean repo\n{r.stderr}"


def test_reset_then_install_rebuilds(client):
    """The whole point: reset + install is a clean re-provision (and the basis of the reinstall verb)."""
    assert client.wsctl("install").returncode == 0
    assert client.wsctl("reset").returncode == 0
    assert client.wsctl("install").returncode == 0, "install could not rebuild after reset"
    for sub in SUBMODULES:
        assert (client.path / sub / DUMMY_FILE[sub]).exists(), f"{sub} not rebuilt after reset+install"


def test_reset_strips_the_invisible_exclude(client):
    """After an invisible install, reset removes the hiding block so a fresh install re-applies it clean."""
    assert client.wsctl("install", "--invisible").returncode == 0
    client.wsctl("reset")
    exclude = client.path / ".git" / "info" / "exclude"
    text = exclude.read_text() if exclude.exists() else ""
    for sub in SUBMODULES:
        assert sub not in text, f"{sub} still excluded after reset — the hiding block wasn't stripped"
