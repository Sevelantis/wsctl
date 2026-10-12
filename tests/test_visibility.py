"""visibility — invisible mode leaves ZERO submodule trace in the client's repo.

Invisible mode (the design default; built opt-in first via `setup --invisible`) keeps the two
managed submodules as plain clones hidden by local `.git/info/exclude` — no committed pin, no
`.gitmodules`, nothing stageable. That structural absence is what makes invisible mode immune to
the whole F1–F6 class (→ visibility.md). These tests assert the real on-disk state matches that
promise exactly; the config files setup also lays are a separate concern and intentionally ignored.
"""

from pathlib import Path

SUBMODULES = (".claude", "devcontainers")
DUMMY_FILE = {".claude": "abc.txt", "devcontainers": "xyz.txt"}


def _status_lines(client):
    out = client.git("status", "--porcelain").stdout.splitlines()
    return [ln.strip() for ln in out if ln.strip()]


def test_invisible_setup_clones_both_with_content(client):
    """Invisible `setup` still delivers a working workspace: both submodules present, with content."""
    r = client.wsctl("setup", "--invisible")
    assert r.returncode == 0, r.stderr
    for sub in SUBMODULES:
        assert (client.path / sub / DUMMY_FILE[sub]).exists(), f"{sub} not cloned in invisible mode\n{r.stderr}"


def test_invisible_leaves_no_committed_submodule_trace(client):
    """The core invisible promise: no `.gitmodules`, and no gitlink staged in the index —
    nothing about the submodules is tracked or pushable."""
    assert client.wsctl("setup", "--invisible").returncode == 0  # not vacuous: setup must have run
    assert not (client.path / ".gitmodules").exists(), ".gitmodules was created — invisible mode must not register submodules"
    staged = client.git("ls-files", "--stage").stdout
    assert "160000 " not in staged, "a gitlink (submodule pin) was staged — invisible mode must leave no pin"


def test_invisible_submodules_are_hidden_from_git_status(client):
    """The folders are hidden via `.git/info/exclude`, so `git status` never lists them —
    the client can `git add .` freely and never scoop up a submodule."""
    assert client.wsctl("setup", "--invisible").returncode == 0  # not vacuous: setup must have run
    lines = _status_lines(client)
    for sub in SUBMODULES:
        assert not any(sub in ln for ln in lines), f"{sub} shows in git status — the exclude isn't hiding it\n{lines}"


def test_invisible_writes_the_exclude_entries(client):
    """The hiding mechanism itself: both submodule paths land in `.git/info/exclude`."""
    client.wsctl("setup", "--invisible")
    exclude = (client.path / ".git" / "info" / "exclude").read_text()
    for sub in SUBMODULES:
        assert sub in exclude, f"{sub} missing from .git/info/exclude — nothing is hiding it"
