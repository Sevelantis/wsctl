"""setup — the one-paste onboarding proof (the base case, UC-1 `fresh-repo`).

This is the end-to-end gap the suite was missing: nothing yet proved that a single
`wsctl setup` takes a *fresh* client repo all the way to a working workspace. Each test
fabricates that fresh-repo state (conftest's `client`) and asserts the real shipped tool
reaches the target — the bookmark's birth path (first-ever `submodule add`). Green here
is the 1:1 promise that a client's first paste lands identically (→ testing.md).
"""

from pathlib import Path

import pytest

# PARKED 2026-10-15 — normal mode (committed pin + .gitmodules + ignore=all) was cut to unblock
# development (invisible is now the only supported mode). This whole file proved the NORMAL-mode
# install base case (`submodule add` = the bookmark's birth); the invisible base case lives in
# test_visibility.py. Kept — not deleted — so it revives with normal mode. → known-issues.md.
# (Coverage note: config-laying — the only mode-agnostic check here — is now asserted for invisible mode in
#  test_visibility.py::test_install_lays_the_config_templates, so skipping this file leaves no coverage gap.)
pytestmark = pytest.mark.skip(reason="normal mode parked 2026-10-15 — invisible-only (→ known-issues.md)")

ROOT = Path(__file__).resolve().parents[1]  # wsctl/
SUBMODULES = (".claude", "devcontainers")
DUMMY_FILE = {".claude": "abc.txt", "devcontainers": "xyz.txt"}
# The config blueprint setup lays down — derived from the real templates/, so it tracks the tool.
TEMPLATES = sorted(p.name for p in (ROOT / "templates").iterdir() if p.is_file())


def test_install_provisions_both_submodules_with_content(client):
    """THE base case: one `setup` on a fresh repo clones BOTH submodules with real content.
    If this fails, a client's very first paste never reaches a working workspace."""
    r = client.wsctl("install")
    assert r.returncode == 0, r.stderr
    for sub in SUBMODULES:
        f = client.path / sub / DUMMY_FILE[sub]
        assert f.exists(), f"{sub} not cloned (missing {DUMMY_FILE[sub]})\n{r.stderr}"
        assert f.read_text().strip(), f"{sub} cloned but {DUMMY_FILE[sub]} is empty"


def test_install_leaves_submodules_on_a_branch(client):
    """Each submodule lands ON its branch, never detached at the pin — this is precisely what
    lets a later `wsctl update` be a plain `git pull`. (setup.sh's `--init` detaches; wsctl must not.)"""
    client.wsctl("install")
    for sub in SUBMODULES:
        head = client.git("-C", sub, "rev-parse", "--abbrev-ref", "HEAD").stdout.strip()
        assert head == "master", f"{sub} is on {head!r}, not a branch — a detached setup breaks `update`"


def test_install_lays_the_config_templates(client):
    """The config half of onboarding: setup copies every templates/ blueprint into the project root
    (.mcp.json/.npmrc/docker-compose.client.yaml). A missing one = a client that can't Rebuild."""
    client.wsctl("install")
    for name in TEMPLATES:
        assert (client.path / name).exists(), f"config template {name} was not laid"


def test_install_sets_ignore_all_both_places(client):
    """`submodule.<name>.ignore=all` must land in BOTH .gitmodules and local .git/config — the quiet
    mode that keeps a floated submodule from nagging the client's `git status`/prompt (F3)."""
    client.wsctl("install")
    for sub in SUBMODULES:
        gm = client.git("config", "-f", ".gitmodules", "--get", f"submodule.{sub}.ignore").stdout.strip()
        local = client.git("config", "--get", f"submodule.{sub}.ignore").stdout.strip()
        assert gm == "all", f"{sub}: .gitmodules ignore is {gm!r}, not 'all'"
        assert local == "all", f"{sub}: local .git/config ignore is {local!r}, not 'all'"


def test_install_is_rerun_safe(client):
    """Re-run safety — the reshaped recovery model (#39): running `setup` a second time is idempotent,
    not destructive. A client who re-pastes the line must land green again, content intact."""
    assert client.wsctl("install").returncode == 0
    r2 = client.wsctl("install")
    assert r2.returncode == 0, f"second setup failed — not idempotent\n{r2.stderr}"
    for sub in SUBMODULES:
        assert (client.path / sub / DUMMY_FILE[sub]).exists(), f"{sub} content lost on re-run"
