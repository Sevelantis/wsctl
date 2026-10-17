"""visibility — invisible install leaves no submodule trace in the client's repo (no pin, no .gitmodules, hidden)."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]  # wsctl/
SUBMODULES = (".claude", "devcontainers")
DUMMY_FILE = {".claude": "abc.txt", "devcontainers": "xyz.txt"}


# --- helpers ---


def _status_lines(client):
    out = client.git("status", "--porcelain").stdout.splitlines()
    return [ln.strip() for ln in out if ln.strip()]


# --- invisible install: clone, hide, no trace ---


def test_invisible_setup_clones_both_with_content(client):
    """Install must still deliver a working workspace: both submodules cloned, with content."""
    r = client.wsctl("install", "--invisible")
    assert r.returncode == 0, r.stderr
    for sub in SUBMODULES:
        assert (client.path / sub / DUMMY_FILE[sub]).exists(), f"{sub} not cloned in invisible mode\n{r.stderr}"


def test_invisible_leaves_no_committed_submodule_trace(client):
    """No `.gitmodules` and no staged submodule pointer; otherwise the submodules could be committed or pushed."""
    assert client.wsctl("install", "--invisible").returncode == 0  # not vacuous: setup must have run
    assert not (client.path / ".gitmodules").exists(), ".gitmodules was created — invisible mode must not register submodules"
    staged = client.git("ls-files", "--stage").stdout
    assert "160000 " not in staged, "a gitlink (submodule pin) was staged — invisible mode must leave no pin"


def test_invisible_submodules_are_hidden_from_git_status(client):
    """`git status` must not list the submodules; otherwise `git add .` would sweep them into the client's commit."""
    assert client.wsctl("install", "--invisible").returncode == 0  # not vacuous: setup must have run
    lines = _status_lines(client)
    for sub in SUBMODULES:
        assert not any(sub in ln for ln in lines), f"{sub} shows in git status — the exclude isn't hiding it\n{lines}"


def test_invisible_writes_the_exclude_entries(client):
    """Both submodule paths must be written to `.git/info/exclude`, or nothing hides them."""
    client.wsctl("install", "--invisible")
    exclude = (client.path / ".git" / "info" / "exclude").read_text()
    for sub in SUBMODULES:
        assert sub in exclude, f"{sub} missing from .git/info/exclude — nothing is hiding it"


def test_invisible_rerun_reapplies_the_exclude(client):
    """`.git/info/exclude` is not cloned, so a re-run must rewrite it; otherwise a re-cloned repo shows the submodules."""
    assert client.wsctl("install", "--invisible").returncode == 0
    exclude = client.path / ".git" / "info" / "exclude"
    exclude.unlink()  # simulate a fresh clone: the exclude is gone
    assert client.wsctl("install", "--invisible").returncode == 0, "re-run failed"
    text = exclude.read_text()
    for sub in SUBMODULES:
        assert sub in text, f"{sub} not re-excluded on re-run — invisibility didn't self-heal"


def test_invisible_update_keeps_zero_trace(client):
    """`update` must not create a pointer or `.gitmodules`, or un-hide a folder, in an invisible workspace."""
    assert client.wsctl("install", "--invisible").returncode == 0
    assert client.wsctl("update").returncode == 0, "update failed in invisible mode"
    assert not (client.path / ".gitmodules").exists(), "update created .gitmodules — broke invisibility"
    assert "160000 " not in client.git("ls-files", "--stage").stdout, "update staged a pin — broke invisibility"
    lines = _status_lines(client)
    for sub in SUBMODULES:
        assert not any(sub in ln for ln in lines), f"{sub} became visible after update\n{lines}"


# --- install: config templates and mode guard ---


def test_install_lays_the_config_templates(client):
    """Every template must land at its relative path; the compose override must go in .devcontainer/, not the root, or it is ignored."""
    tdir = ROOT / "templates"
    rels = sorted(p.relative_to(tdir).as_posix() for p in tdir.rglob("*") if p.is_file())
    assert rels, "no templates found to lay — fixture/tree problem"
    assert client.wsctl("install").returncode == 0
    for rel in rels:
        assert (client.path / rel).exists(), f"config template {rel} was not laid at its correct relative path by install"
    # the compose override belongs under .devcontainer/, never flattened to the project root
    assert (client.path / ".devcontainer" / "docker-compose.client.yaml").exists(), \
        "docker-compose.client.yaml missing from .devcontainer/ — the devcontainer can't find its client override"
    assert not (client.path / "docker-compose.client.yaml").exists(), \
        "docker-compose.client.yaml was laid at the project root — it belongs in .devcontainer/"


def test_install_rejects_the_unsupported_normal_mode(client):
    """WSCTL_MODE=normal must fail immediately with a clear message and change nothing."""
    r = client.wsctl("install", extra_env={"WSCTL_MODE": "normal"})
    assert r.returncode != 0, "normal mode should be rejected, not run"
    assert "not supported" in r.stderr.lower() or "parked" in r.stderr.lower(), f"no clear unsupported message\n{r.stderr}"
    # the guard runs before any work, so nothing is provisioned or laid
    assert not (client.path / ".claude" / ".git").exists(), "normal mode cloned a submodule before failing"
    assert not (client.path / ".mcp.json").exists(), "normal mode laid config before failing"


def test_invisible_hides_the_wsctl_launcher_dir(client):
    """The `.wsctl/` launcher clone must be excluded too, or it shows up untracked in `git status`."""
    assert client.wsctl("install").returncode == 0
    exclude = (client.path / ".git" / "info" / "exclude").read_text()
    assert "/.wsctl/" in exclude, "the launcher dir isn't excluded — .wsctl/ leaks into git status"
    # confirm the exclude hides a real .wsctl/ directory
    (client.path / ".wsctl").mkdir(exist_ok=True)
    (client.path / ".wsctl" / "wsctl.sh").write_text("# launcher stand-in\n")
    lines = _status_lines(client)
    assert not any(".wsctl" in ln for ln in lines), f".wsctl/ shows in git status despite the exclude\n{lines}"


# --- install: .env summary ---


def test_install_never_prints_the_token_value(client):
    """Security: the .env summary may report that the token key is set, but must never print its value."""
    r = client.wsctl("install")
    assert r.returncode == 0, r.stderr
    combined = r.stdout + r.stderr
    token_val = ""
    for line in (client.path / ".env").read_text().splitlines():
        if line.startswith("GH_TOKEN_RO_INFRA="):
            token_val = line.split("=", 1)[1]
    assert token_val, "fixture precondition: a token value must be set"
    assert token_val not in combined, "install printed the token value — secrets must never be echoed"
    assert "GH_TOKEN_RO_INFRA" in combined, "install didn't report the token key's presence"


def test_install_flags_an_unset_rebuild_key(client):
    """An unset required key (only the token is set here) must be named, or the user cannot tell what to fix before Rebuild."""
    r = client.wsctl("install")
    combined = r.stdout + r.stderr
    assert "COMPOSE_PROJECT_NAME" in combined, "the summary didn't mention the required Rebuild key"
    assert "not set" in combined.lower(), "an unset key wasn't flagged — the user can't tell what's missing"


def test_install_does_not_nag_when_env_is_complete(client):
    """With every required key set, the summary must not tell the user to set anything."""
    env = client.path / ".env"
    env.write_text(env.read_text() + "COMPOSE_PROJECT_NAME=demo\nDEVCONTAINER_INGRESS_PORT=8080\n")
    r = client.wsctl("install")
    combined = (r.stdout + r.stderr).lower()
    assert "not set" not in combined, f"a key was flagged unset though all are present\n{combined}"
