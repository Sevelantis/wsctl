"""install (standard-submodule mode) — one install takes a fresh repo to a working workspace; currently skipped."""

from pathlib import Path

import pytest

# These tests cover the standard-submodule mode, which is not implemented yet; invisible mode is tested in
# test_visibility.py (including config templates). Kept so they can be re-enabled with that mode.
pytestmark = pytest.mark.skip(reason="standard-submodule mode is not implemented; invisible mode is tested in test_visibility.py")

ROOT = Path(__file__).resolve().parents[1]  # wsctl/
SUBMODULES = (".claude", "devcontainers")
DUMMY_FILE = {".claude": "abc.txt", "devcontainers": "xyz.txt"}
# The config files install lays down, read from the real templates/ directory.
TEMPLATES = sorted(p.name for p in (ROOT / "templates").iterdir() if p.is_file())


def test_install_provisions_both_submodules_with_content(client):
    """One install on a fresh repo must clone both submodules with content, or a first-time client gets nothing."""
    r = client.wsctl("install")
    assert r.returncode == 0, r.stderr
    for sub in SUBMODULES:
        f = client.path / sub / DUMMY_FILE[sub]
        assert f.exists(), f"{sub} not cloned (missing {DUMMY_FILE[sub]})\n{r.stderr}"
        assert f.read_text().strip(), f"{sub} cloned but {DUMMY_FILE[sub]} is empty"


def test_install_leaves_submodules_on_a_branch(client):
    """Submodules must land on a branch, not a detached HEAD, or a later `update` cannot pull."""
    client.wsctl("install")
    for sub in SUBMODULES:
        head = client.git("-C", sub, "rev-parse", "--abbrev-ref", "HEAD").stdout.strip()
        assert head == "master", f"{sub} is on {head!r}, not a branch — a detached setup breaks `update`"


def test_install_lays_the_config_templates(client):
    """Every template must be copied into the project; a missing one means the client cannot Rebuild."""
    client.wsctl("install")
    for name in TEMPLATES:
        assert (client.path / name).exists(), f"config template {name} was not laid"


def test_install_sets_ignore_all_both_places(client):
    """`submodule.<name>.ignore=all` must be set in both .gitmodules and .git/config, or `git status` and the prompt nag about submodules."""
    client.wsctl("install")
    for sub in SUBMODULES:
        gm = client.git("config", "-f", ".gitmodules", "--get", f"submodule.{sub}.ignore").stdout.strip()
        local = client.git("config", "--get", f"submodule.{sub}.ignore").stdout.strip()
        assert gm == "all", f"{sub}: .gitmodules ignore is {gm!r}, not 'all'"
        assert local == "all", f"{sub}: local .git/config ignore is {local!r}, not 'all'"


def test_install_is_rerun_safe(client):
    """A second install must succeed and keep content intact, so re-running the command is always safe."""
    assert client.wsctl("install").returncode == 0
    r2 = client.wsctl("install")
    assert r2.returncode == 0, f"second setup failed — not idempotent\n{r2.stderr}"
    for sub in SUBMODULES:
        assert (client.path / sub / DUMMY_FILE[sub]).exists(), f"{sub} content lost on re-run"
