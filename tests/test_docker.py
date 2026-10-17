"""docker — `wsctl docker` routes to the right script with every flag intact; the scripts are stubbed, Docker is never run."""

import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]  # wsctl/
STUB = '#!/usr/bin/env bash\necho "STUB $(basename "$0") ARGS: $*"\n'
WRAPPED = ("docker-space-audit.sh", "docker-cleanup.sh")


# --- helpers ---


def _stage(tmp_path, keep_all=True):
    """Copy the real tool into tmp; swap the wrapped docker scripts for arg-recording stubs."""
    home = tmp_path / "tool"
    shutil.copytree(
        ROOT,
        home,
        ignore=shutil.ignore_patterns(
            "tests", ".git", "__pycache__", ".pytest_cache", ".ruff_cache"
        ),
    )
    dockerdir = home / "lib" / "docker"
    for s in WRAPPED:
        if keep_all:
            (dockerdir / s).write_text(STUB)
            (dockerdir / s).chmod(0o755)
    return home


def _run(home, *args):
    return subprocess.run(
        ["bash", str(home / "wsctl.sh"), "docker", *args],
        text=True,
        capture_output=True,
    )


# --- routing and help ---


def test_bare_docker_prints_help(tmp_path):
    """`wsctl docker` with no subcommand greets with help, lists audit+clean, exits 0."""
    r = _run(_stage(tmp_path))
    assert r.returncode == 0
    assert "audit" in r.stderr and "clean" in r.stderr


def test_help_flag_prints_help(tmp_path):
    """`wsctl docker --help` is the same help, exit 0."""
    r = _run(_stage(tmp_path), "--help")
    assert r.returncode == 0
    assert "wsctl docker" in r.stderr


def test_audit_routes_and_forwards_flags(tmp_path):
    """`wsctl docker audit -v` reaches docker-space-audit.sh with -v intact."""
    r = _run(_stage(tmp_path), "audit", "-v")
    assert r.returncode == 0
    assert "STUB docker-space-audit.sh ARGS: -v" in r.stdout


def test_clean_routes_and_forwards_all_flags(tmp_path):
    """`wsctl docker clean --volumes --dry-run` reaches docker-cleanup.sh with every flag, in order."""
    r = _run(_stage(tmp_path), "clean", "--volumes", "--dry-run")
    assert r.returncode == 0
    assert "STUB docker-cleanup.sh ARGS: --volumes --dry-run" in r.stdout


# --- failure modes ---


def test_unknown_subcommand_fails_cleanly(tmp_path):
    """An unknown subcommand is a non-zero, named error — not a silent no-op or stack trace."""
    r = _run(_stage(tmp_path), "frobnicate")
    assert r.returncode != 0
    assert "unknown" in r.stderr.lower() and "frobnicate" in r.stderr


def test_backup_is_held_behind_with_guidance(tmp_path):
    """`backup` is not available yet; it must point at the `docker-backup` alias instead of pretending to work."""
    r = _run(_stage(tmp_path), "backup")
    assert r.returncode != 0
    assert "docker-backup" in r.stderr


def test_missing_wrapped_script_errors(tmp_path):
    """If a wrapped script is absent (a broken install), fail clearly — never a bare bash error."""
    home = _stage(tmp_path)
    (home / "lib" / "docker" / "docker-cleanup.sh").unlink()
    r = _run(home, "clean")
    assert r.returncode != 0
    assert "missing" in r.stderr.lower()


@pytest.mark.skip(
    reason="no Docker in the sandbox; audit/clean behavior can only be checked on a host with Docker"
)
def test_docker_behavior_host_only():
    """Placeholder: real Docker behavior needs a host with Docker and is not tested here."""
