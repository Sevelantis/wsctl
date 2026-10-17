"""status — the read-only command and the --help / --no-color output contract."""


def test_status_runs_from_project_root_and_names_both_submodules(client):
    """Run from the project root, status must report this repo's submodules."""
    r = client.wsctl("status")
    assert r.returncode == 0, r.stderr
    assert ".claude" in r.stderr and "devcontainers" in r.stderr


def test_status_reports_not_cloned_before_setup(client):
    """A fresh repo has no submodule checkouts yet — status must say so, not crash."""
    r = client.wsctl("status")
    assert "not cloned" in r.stderr


def test_help_lists_the_verbs(client):
    """--help must exit 0 on stdout and name the main commands."""
    r = client.wsctl("--help")
    assert r.returncode == 0
    assert all(verb in r.stdout for verb in ("install", "update", "status"))


def test_no_color_emits_no_ansi(client):
    """--no-color must be applied before colours are defined, so no ANSI codes appear."""
    r = client.wsctl("--no-color", "status")
    assert "\x1b[" not in (r.stdout + r.stderr)
