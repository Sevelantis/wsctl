"""status — the read-only verb: no token, no network. Also the first proof the harness + ROOT contract work."""


def test_status_runs_from_project_root_and_names_both_submodules(client):
    """Guards the ROOT=$PWD contract: run from the project root, status must see THIS repo's submodules."""
    r = client.wsctl("status")
    assert r.returncode == 0, r.stderr
    assert ".claude" in r.stderr and "devcontainers" in r.stderr


def test_status_reports_not_cloned_before_setup(client):
    """A fresh repo has no submodule checkouts yet — status must say so, not crash."""
    r = client.wsctl("status")
    assert "not cloned" in r.stderr


def test_help_lists_the_verbs(client):
    """--help is the public contract; it must exit 0 (to stdout) and name every shipped verb."""
    r = client.wsctl("--help")
    assert r.returncode == 0
    assert all(verb in r.stdout for verb in ("setup", "update", "status"))


def test_no_color_emits_no_ansi(client):
    """The --no-color pre-scan must run before any colour var is set — zero ANSI in the output."""
    r = client.wsctl("--no-color", "status")
    assert "\x1b[" not in (r.stdout + r.stderr)
