"""output — the verbose window, the version command, and the promises that make them safe.

wsctl stays terse by default; `-v`/`--verbose` (or WSCTL_VERBOSE=1) opens a window onto the plumbing — the
resolved paths and the git commands it runs. Two promises make that window safe to open: it never prints the
token, and it is not a raw `set -x` trace. `version` reports which tool a client is running. These cover the
real risks: a leak through verbose, an accidental xtrace, verbose bleeding into the quiet default, and version
working with no key or network.
"""

from conftest import DUMMY_TOKEN

VERBOSE_MARK = "»"  # debug() prefixes every verbose-only line with this, and nothing else emits it


# --- verbose reveals more, quietly by default ---


def test_default_install_shows_no_verbose_plumbing(client):
    """With no verbose flag, the calm surface has none of the debug plumbing lines."""
    r = client.wsctl("install")
    assert r.returncode == 0, r.stderr
    assert VERBOSE_MARK not in r.stderr, "plumbing leaked into the default (quiet) output"


def test_verbose_flag_reveals_the_plumbing(client):
    """`-v install` adds debug lines (resolved paths, the clone command) the default run hid.

    -v is a global, so it leads the command — flags after the command belong to the command (e.g. docker).
    """
    r = client.wsctl("-v", "install")
    assert r.returncode == 0, r.stderr
    assert VERBOSE_MARK in r.stderr, "-v did not reveal any plumbing"
    assert "clone" in r.stderr, "the clone command was not shown under -v"


def test_wsctl_verbose_env_matches_the_flag(client):
    """WSCTL_VERBOSE=1 turns on the same window as -v, for wrapping a run without changing the invocation."""
    r = client.wsctl("install", extra_env={"WSCTL_VERBOSE": "1"})
    assert r.returncode == 0, r.stderr
    assert VERBOSE_MARK in r.stderr, "WSCTL_VERBOSE=1 did not enable verbose"


# --- the two promises that make verbose safe ---


def test_verbose_never_prints_the_token(client):
    """Even wide open, the token appears in neither stdout nor stderr — the security invariant."""
    r = client.wsctl("-v", "install", extra_env={"WSCTL_VERBOSE": "1"})
    assert r.returncode == 0, r.stderr
    assert DUMMY_TOKEN not in r.stdout, "the token leaked to stdout under verbose"
    assert DUMMY_TOKEN not in r.stderr, "the token leaked to stderr under verbose"


def test_verbose_is_not_a_set_x_trace(client):
    """Verbose is curated detail, not shell xtrace: no `+ `-prefixed trace lines appear."""
    r = client.wsctl("-v", "install")
    assert r.returncode == 0, r.stderr
    lines = r.stderr.splitlines()
    assert not any(ln.startswith(("+ ", "++ ")) for ln in lines), "looks like `set -x` xtrace, not curated verbose"


# --- version ---


def test_version_subcommand_prints_the_tool_version(client):
    """`wsctl version` prints `wsctl <ver>` to stdout and exits zero."""
    r = client.wsctl("version")
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip().startswith("wsctl "), f"unexpected version line: {r.stdout!r}"
    assert "0.1.0" in r.stdout, f"VERSION file not reflected: {r.stdout!r}"


def test_version_flags_match_the_subcommand(client):
    """`--version` and `-V` print the same line as the `version` subcommand."""
    base = client.wsctl("version").stdout.strip()
    for flag in ("--version", "-V"):
        r = client.wsctl(flag)
        assert r.returncode == 0, r.stderr
        assert r.stdout.strip() == base, f"{flag} disagreed with `version`: {r.stdout!r} vs {base!r}"


def test_version_needs_no_key_or_network(client, tmp_path):
    """version is pure local read: it works in a bare dir with no .env and no remotes configured."""
    bare = tmp_path / "empty"
    bare.mkdir()
    r = client.wsctl("version")  # client repo has a dummy .env, but version must not consult it
    assert r.returncode == 0, r.stderr
    # and with the token var explicitly absent from the environment, it still prints:
    r2 = client.wsctl("version", extra_env={"GH_TOKEN_RO_INFRA": ""})
    assert r2.returncode == 0 and r2.stdout.strip().startswith("wsctl ")
