"""visibility — invisible is the ONLY mode: install leaves ZERO submodule trace in the client's repo.

Invisible mode keeps the two managed submodules as plain clones hidden by local `.git/info/exclude` —
no committed pin, no `.gitmodules`, nothing stageable — which makes it immune to the whole F1–F6 class
(→ visibility.md). This file is also the home of the invisible `install` base case (the normal-mode
`test_install.py` is skipped). It asserts the on-disk submodule state AND the config half of install
(templates laid), plus that the parked `WSCTL_MODE=normal` is rejected fast.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]  # wsctl/
SUBMODULES = (".claude", "devcontainers")
DUMMY_FILE = {".claude": "abc.txt", "devcontainers": "xyz.txt"}


def _status_lines(client):
    out = client.git("status", "--porcelain").stdout.splitlines()
    return [ln.strip() for ln in out if ln.strip()]


def test_invisible_setup_clones_both_with_content(client):
    """Invisible `setup` still delivers a working workspace: both submodules present, with content."""
    r = client.wsctl("install", "--invisible")
    assert r.returncode == 0, r.stderr
    for sub in SUBMODULES:
        assert (client.path / sub / DUMMY_FILE[sub]).exists(), f"{sub} not cloned in invisible mode\n{r.stderr}"


def test_invisible_leaves_no_committed_submodule_trace(client):
    """The core invisible promise: no `.gitmodules`, and no gitlink staged in the index —
    nothing about the submodules is tracked or pushable."""
    assert client.wsctl("install", "--invisible").returncode == 0  # not vacuous: setup must have run
    assert not (client.path / ".gitmodules").exists(), ".gitmodules was created — invisible mode must not register submodules"
    staged = client.git("ls-files", "--stage").stdout
    assert "160000 " not in staged, "a gitlink (submodule pin) was staged — invisible mode must leave no pin"


def test_invisible_submodules_are_hidden_from_git_status(client):
    """The folders are hidden via `.git/info/exclude`, so `git status` never lists them —
    the client can `git add .` freely and never scoop up a submodule."""
    assert client.wsctl("install", "--invisible").returncode == 0  # not vacuous: setup must have run
    lines = _status_lines(client)
    for sub in SUBMODULES:
        assert not any(sub in ln for ln in lines), f"{sub} shows in git status — the exclude isn't hiding it\n{lines}"


def test_invisible_writes_the_exclude_entries(client):
    """The hiding mechanism itself: both submodule paths land in `.git/info/exclude`."""
    client.wsctl("install", "--invisible")
    exclude = (client.path / ".git" / "info" / "exclude").read_text()
    for sub in SUBMODULES:
        assert sub in exclude, f"{sub} missing from .git/info/exclude — nothing is hiding it"


def test_invisible_rerun_reapplies_the_exclude(client):
    """Per-clone self-heal: `.git/info/exclude` never travels, so a fresh clone starts visible. Re-running
    invisible `setup` must re-write the exclude — otherwise a re-cloned repo leaks the submodules forever."""
    assert client.wsctl("install", "--invisible").returncode == 0
    exclude = client.path / ".git" / "info" / "exclude"
    exclude.unlink()  # simulate a fresh clone: the exclude is gone
    assert client.wsctl("install", "--invisible").returncode == 0, "re-run failed"
    text = exclude.read_text()
    for sub in SUBMODULES:
        assert sub in text, f"{sub} not re-excluded on re-run — invisibility didn't self-heal"


def test_invisible_update_keeps_zero_trace(client):
    """`update` on an invisible workspace must stay invisible: it pulls the plain clones but must never
    create a pin/.gitmodules or un-hide a folder. (The pull mechanic itself is proven-live separately.)"""
    assert client.wsctl("install", "--invisible").returncode == 0
    assert client.wsctl("update").returncode == 0, "update failed in invisible mode"
    assert not (client.path / ".gitmodules").exists(), "update created .gitmodules — broke invisibility"
    assert "160000 " not in client.git("ls-files", "--stage").stdout, "update staged a pin — broke invisibility"
    lines = _status_lines(client)
    for sub in SUBMODULES:
        assert not any(sub in ln for ln in lines), f"{sub} became visible after update\n{lines}"


def test_install_lays_the_config_templates(client):
    """The config HALF of a working install (the other half of the submodule clone): `install` copies every
    templates/ blueprint (.mcp.json, .npmrc, docker-compose.client.yaml) into the project root. A missing one
    = a client that can't Rebuild. This is the ONLY assertion of config-laying now that test_install.py is
    skipped — the coverage gap it leaves, closed."""
    templates = sorted(p.name for p in (ROOT / "templates").iterdir() if p.is_file())
    assert templates, "no templates found to lay — fixture/tree problem"
    assert client.wsctl("install").returncode == 0
    for name in templates:
        assert (client.path / name).exists(), f"config template {name} was not laid by install"


def test_install_rejects_the_unsupported_normal_mode(client):
    """WSCTL_MODE=normal is PARKED: choosing it must fail FAST with a clear 'not supported' message and lay
    NOTHING — that clean error is the whole UX of the parked seam (→ known-issues.md). Proves the wiring of
    the reserved normal-mode seam without implementing it."""
    r = client.wsctl("install", extra_env={"WSCTL_MODE": "normal"})
    assert r.returncode != 0, "normal mode should be rejected, not run"
    assert "not supported" in r.stderr.lower() or "parked" in r.stderr.lower(), f"no clear unsupported message\n{r.stderr}"
    # fast-fail: the guard runs before any work, so nothing is provisioned or laid
    assert not (client.path / ".claude" / ".git").exists(), "normal mode cloned a submodule before failing — not fast-fail"
    assert not (client.path / ".mcp.json").exists(), "normal mode laid config before failing — not fast-fail"
