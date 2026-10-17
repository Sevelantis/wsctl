"""update — pulls the managed submodules; covers narrowing, dirty-discard, detached HEAD, and the missing-token guard."""

SUBMODULES = (".claude", "devcontainers")
DUMMY_FILE = {".claude": "abc.txt", "devcontainers": "xyz.txt"}
TOKEN_VAR = "GH_TOKEN_RO_INFRA"


def _setup(client):
    assert client.wsctl("install").returncode == 0, "precondition: setup must succeed"


def test_update_pulls_both_submodules(client):
    """The happy path: after setup, `update` fast-forwards both submodules and exits clean."""
    _setup(client)
    r = client.wsctl("update")
    assert r.returncode == 0, r.stderr
    for sub in SUBMODULES:
        assert sub in r.stderr, f"{sub} not reported by update\n{r.stderr}"


def test_update_can_narrow_to_one_submodule(client):
    """`update <submodule>` touches only that one — the client can refresh a single folder."""
    _setup(client)
    r = client.wsctl("update", "devcontainers")
    assert r.returncode == 0, r.stderr
    assert "devcontainers" in r.stderr and ".claude" not in r.stderr, f"narrowing failed\n{r.stderr}"


def test_update_discards_a_dirty_managed_submodule(client):
    """Local edits in a managed submodule would block the pull; update must discard them and still succeed."""
    _setup(client)
    f = client.path / ".claude" / DUMMY_FILE[".claude"]
    f.write_text("local junk that would block a pull\n")
    r = client.wsctl("update")
    assert r.returncode == 0, f"update did not survive a dirty submodule\n{r.stderr}"
    assert "local junk" not in f.read_text(), "the local edit was not discarded"


def test_update_refuses_a_detached_submodule(client):
    """A detached submodule has no branch to fast-forward; update must warn and skip it, never crash."""
    _setup(client)
    client.git("-C", ".claude", "checkout", "--detach", "HEAD")
    r = client.wsctl("update", ".claude")
    assert r.returncode != 0, "update should report a non-zero when a submodule is unpullable"
    assert "detached" in r.stderr.lower(), f"no clear detached-HEAD diagnostic\n{r.stderr}"


def test_update_without_a_token_dies_clearly(client):
    """Without a token, update must stop with a message naming the token variable, not a git error."""
    _setup(client)
    (client.path / ".env").write_text("# no token here\n")
    r = client.wsctl("update")
    assert r.returncode != 0, "update ran without a token"
    assert TOKEN_VAR in r.stderr, f"the missing-token message should name {TOKEN_VAR}\n{r.stderr}"
