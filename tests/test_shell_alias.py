"""shell alias — install wires a `wsctl` command into the user's shell startup file; reset removes it.

The function written into the rc is version-less and path-less: it walks up from wherever you stand to the
nearest .wsctl/wsctl.sh and runs that project's own tool. Editing a file outside the project is delicate, so
these cover the real corner cases: the right rc per shell, idempotent rewrites, an unknown shell, an unwritable
rc (never fatal), removal on reset, and that the written function actually resolves and runs the tool.
"""

import shutil
import subprocess
from pathlib import Path

TOOL = Path(__file__).resolve().parents[1]      # the wsctl/ checkout under test
BEGIN = "# wsctl-alias-begin"


def _home(tmp_path: Path) -> Path:
    h = tmp_path / "home"
    h.mkdir()
    return h


def _deploy(repo: Path) -> Path:
    """Lay the tool out as a real client has it: cloned into <project>/.wsctl/ (so the locator has a target)."""
    wsctl_dir = repo / ".wsctl"
    wsctl_dir.mkdir()
    for item in ("wsctl.sh", "lib", "templates"):
        src = TOOL / item
        (shutil.copytree if src.is_dir() else shutil.copy2)(src, wsctl_dir / item)
    return wsctl_dir


def test_install_writes_the_wsctl_function_to_the_zsh_rc(client, tmp_path):
    """A zsh user gets the marked wsctl function in ~/.zshrc."""
    home = _home(tmp_path)
    r = client.wsctl("install", extra_env={"HOME": str(home), "SHELL": "/bin/zsh"})
    assert r.returncode == 0, r.stderr
    rc = home / ".zshrc"
    assert rc.exists(), "install did not create ~/.zshrc"
    text = rc.read_text()
    assert BEGIN in text and "wsctl()" in text, "the wsctl function was not written"


def test_install_targets_the_bash_rc_for_a_bash_shell(client, tmp_path):
    """A bash user gets ~/.bashrc, never ~/.zshrc."""
    home = _home(tmp_path)
    assert client.wsctl("install", extra_env={"HOME": str(home), "SHELL": "/bin/bash"}).returncode == 0
    assert (home / ".bashrc").exists() and BEGIN in (home / ".bashrc").read_text()
    assert not (home / ".zshrc").exists(), "wrote the wrong shell's rc"


def test_install_also_wires_an_existing_other_shell_rc(client, tmp_path):
    """Login shell ($SHELL) and interactive shell can differ: if a ~/.zshrc already exists under a bash $SHELL,
    the command must land in BOTH, so `wsctl` is defined whichever shell the user actually types in."""
    home = _home(tmp_path)
    (home / ".zshrc").write_text("# an existing zsh user's rc\n")
    r = client.wsctl("install", extra_env={"HOME": str(home), "SHELL": "/bin/bash"})
    assert r.returncode == 0, r.stderr
    assert BEGIN in (home / ".bashrc").read_text(), "the $SHELL (bash) rc was not wired"
    assert BEGIN in (home / ".zshrc").read_text(), "the existing zsh rc was not wired — the mismatch bug"


def test_install_honors_zdotdir_for_zsh(client, tmp_path):
    """A zsh user with ZDOTDIR set gets $ZDOTDIR/.zshrc, not $HOME/.zshrc (the devcontainer trap)."""
    home = _home(tmp_path)
    zdot = tmp_path / "zdot"
    zdot.mkdir()
    r = client.wsctl("install", extra_env={"HOME": str(home), "SHELL": "/bin/zsh", "ZDOTDIR": str(zdot)})
    assert r.returncode == 0, r.stderr
    assert BEGIN in (zdot / ".zshrc").read_text(), "ZDOTDIR's .zshrc was not wired"
    assert not (home / ".zshrc").exists(), "wrote $HOME/.zshrc instead of ZDOTDIR's"


def test_install_is_idempotent_in_the_rc(client, tmp_path):
    """Re-running install refreshes the block in place — it never piles up."""
    home = _home(tmp_path)
    env = {"HOME": str(home), "SHELL": "/bin/zsh"}
    assert client.wsctl("install", extra_env=env).returncode == 0
    assert client.wsctl("install", extra_env=env).returncode == 0
    assert (home / ".zshrc").read_text().count(BEGIN) == 1, "the alias block was duplicated on re-install"


def test_install_skips_quietly_for_an_unknown_shell(client, tmp_path):
    """An unsupported shell is not fatal: install succeeds, nothing is written, the reason is reported."""
    home = _home(tmp_path)
    r = client.wsctl("install", extra_env={"HOME": str(home), "SHELL": "/usr/bin/fish"})
    assert r.returncode == 0, r.stderr
    assert not (home / ".zshrc").exists() and not (home / ".bashrc").exists()
    assert "not set up, because" in r.stderr, "no explicit reason logged for the skip"


def test_an_unwritable_rc_does_not_fail_install(client, tmp_path):
    """If the rc cannot be written, install still succeeds and says why — the user can run the tool by path."""
    home = _home(tmp_path)
    rc = home / ".zshrc"
    rc.write_text("# existing user content\n")
    rc.chmod(0o444)
    try:
        r = client.wsctl("install", extra_env={"HOME": str(home), "SHELL": "/bin/zsh"})
    finally:
        rc.chmod(0o644)
    assert r.returncode == 0, r.stderr
    assert BEGIN not in rc.read_text(), "wrote into an unwritable rc"
    assert "not set up" in r.stderr and "not writable" in r.stderr, "no clear 'why' for the skip"


def test_reset_removes_the_wsctl_function_from_the_rc(client, tmp_path):
    """reset takes our block back out (only ours), leaving the rest of the rc intact."""
    home = _home(tmp_path)
    env = {"HOME": str(home), "SHELL": "/bin/zsh"}
    rc = home / ".zshrc"
    rc.write_text("# existing user content\n")
    assert client.wsctl("install", extra_env=env).returncode == 0
    assert BEGIN in rc.read_text()
    assert client.wsctl("reset", extra_env=env).returncode == 0
    text = rc.read_text()
    assert BEGIN not in text, "reset left the wsctl function behind"
    assert "# existing user content" in text, "reset clobbered the user's own rc content"


def test_install_keeps_an_rc_valid_when_it_lacks_a_trailing_newline(client, tmp_path):
    """An rc whose last line has no trailing newline (e.g. a venv-activate snippet ending in `fi`) must not get
    our marker glued onto it. Before the newline guard, the block appended as `fi# wsctl-alias-begin`, which
    leaves the `if` unterminated — a syntax error that breaks the shell and our own block-strip."""
    home = _home(tmp_path)
    rc = home / ".bashrc"
    rc.write_text(
        'if [ -f "${PWD}/.venv/bin/activate" ];then\n'
        '    source "${PWD}/.venv/bin/activate" > /dev/null 2>&1\n'
        "fi"  # deliberately NO trailing newline — the trigger
    )
    r = client.wsctl("install", extra_env={"HOME": str(home), "SHELL": "/bin/bash"})
    assert r.returncode == 0, r.stderr
    text = rc.read_text()
    assert "fi# wsctl-alias-begin" not in text, "the marker glued onto the previous line (no newline guard)"
    assert BEGIN in text, "the wsctl block was not written"
    syntax = subprocess.run(["bash", "-n", str(rc)], text=True, capture_output=True)
    assert syntax.returncode == 0, f"install left the rc syntactically broken:\n{syntax.stderr}"


def test_the_written_function_resolves_and_runs_from_a_subdir(client, tmp_path):
    """Source the rc, then `wsctl` from a deep subdir must find and run the project's own tool."""
    home = _home(tmp_path)
    wsctl_dir = _deploy(client.path)
    env = {**client.env, "HOME": str(home), "SHELL": "/bin/bash"}
    install = subprocess.run(
        ["bash", str(wsctl_dir / "wsctl.sh"), "install"],
        cwd=str(client.path), env=env, text=True, capture_output=True,
    )
    assert install.returncode == 0, install.stderr
    rc = home / ".bashrc"
    subdir = client.path / "src" / "deep"
    subdir.mkdir(parents=True)
    proof = subprocess.run(
        ["bash", "-c", f'. "{rc}"; wsctl status'],
        cwd=str(subdir), env=env, text=True, capture_output=True,
    )
    assert proof.returncode == 0, f"wsctl via the rc function failed\n{proof.stderr}"
    assert ".claude" in proof.stderr, "the function did not run the project's tool (status output missing)"
