"""reinstall — reset then install: rebuild a clean submodule set (the explicit "give me a clean env" verb).

reinstall is a thin composition: `reset` tears down the submodules' local git-state, then `install`
re-provisions them (invisible). Its job is to DELIVER A CLEAN ENVIRONMENT — so the tests fabricate the
real messy states a client hits and assert the real on-disk outcome, never a mock. The step-level
mechanics are owned by the composed verbs' own suites (test_reset.py proves reset removes folders +
.git/modules + the exclude; test_visibility.py proves invisible install clones + hides); here we prove
the COMPOSITION delivers clean, and that the reset half genuinely ran (stale content is gone).
No mocks: conftest gives a real throwaway git repo + real local bare remotes + the real git binary.
"""

import shutil

SUBMODULES = (".claude", "devcontainers")
DUMMY_FILE = {".claude": "abc.txt", "devcontainers": "xyz.txt"}
SHARED = (".mcp.json", ".npmrc", "docker-compose.client.yaml", ".env")
TOKEN_VAR = "GH_TOKEN_RO_INFRA"


def _install(client):
    assert client.wsctl("install").returncode == 0, "precondition: install must succeed"


def test_reinstall_delivers_a_clean_workspace(client):
    """The happy path: after a working install, `reinstall` still lands both submodules present, with
    content, on their branch — a clean environment, exit 0."""
    _install(client)
    r = client.wsctl("reinstall")
    assert r.returncode == 0, f"reinstall failed on a healthy workspace\n{r.stderr}"
    for sub in SUBMODULES:
        f = client.path / sub / DUMMY_FILE[sub]
        assert f.exists() and f.read_text().strip(), f"{sub} not rebuilt clean by reinstall\n{r.stderr}"
        head = client.git("-C", sub, "rev-parse", "--abbrev-ref", "HEAD").stdout.strip()
        assert head == "master", f"{sub} not on its branch after reinstall (on {head!r})"


def test_reinstall_discards_tangled_state_and_rebuilds(client):
    """The real recovery use-case: a submodule got tangled (local junk + detached). reinstall must RESET
    it (the junk is gone — proof the reset half ran) and re-install it fresh on its branch."""
    _install(client)
    junk = client.path / ".claude" / "LOCAL_JUNK.txt"
    junk.write_text("stale local state that a clean rebuild must erase\n")
    client.git("-C", ".claude", "checkout", "--detach", "HEAD")
    r = client.wsctl("reinstall")
    assert r.returncode == 0, f"reinstall failed to recover a tangled submodule\n{r.stderr}"
    assert not junk.exists(), "stale junk survived — the reset half did not run"
    assert (client.path / ".claude" / DUMMY_FILE[".claude"]).exists(), ".claude not re-cloned by reinstall"
    head = client.git("-C", ".claude", "rev-parse", "--abbrev-ref", "HEAD").stdout.strip()
    assert head == "master", f".claude still detached after reinstall (on {head!r})"


def test_reinstall_works_from_scratch(client):
    """reinstall on a fresh repo (nothing provisioned yet) is safe: the reset half is a no-op, the install
    half provisions — so it behaves like install, never errors on 'nothing to reset'."""
    r = client.wsctl("reinstall")
    assert r.returncode == 0, f"reinstall errored from scratch\n{r.stderr}"
    for sub in SUBMODULES:
        assert (client.path / sub / DUMMY_FILE[sub]).exists(), f"{sub} not provisioned by reinstall-from-scratch"


def test_reinstall_preserves_invisibility(client):
    """reinstall must leave the workspace invisible, like install: no .gitmodules, no staged pin, hidden."""
    _install(client)
    assert client.wsctl("reinstall").returncode == 0
    assert not (client.path / ".gitmodules").exists(), "reinstall created .gitmodules — broke invisibility"
    assert "160000 " not in client.git("ls-files", "--stage").stdout, "reinstall staged a pin — broke invisibility"
    exclude = (client.path / ".git" / "info" / "exclude").read_text()
    for sub in SUBMODULES:
        assert sub in exclude, f"{sub} not hidden after reinstall"


def test_reinstall_never_touches_shared_files(client):
    """The ownership boundary through the composition: reset never touches shared files and install only
    fills-if-absent — so a client's co-owned files must survive a reinstall untouched."""
    _install(client)
    markers = {}
    for name in SHARED:
        p = client.path / name
        markers[name] = (p.read_text() if p.exists() else "") + "# client-owned marker\n"
        p.write_text(markers[name])
    assert client.wsctl("reinstall").returncode == 0
    for name in SHARED:
        assert (client.path / name).read_text() == markers[name], f"reinstall altered a shared file: {name}"


def test_reinstall_without_a_token_dies_clearly(client):
    """reinstall needs the key (its install half re-clones): with no token it must hard-stop with a plain
    message naming the token var, not a cryptic git error."""
    _install(client)
    (client.path / ".env").write_text("# no token here\n")
    r = client.wsctl("reinstall")
    assert r.returncode != 0, "reinstall ran without a token"
    assert TOKEN_VAR in r.stderr, f"the missing-token message should name {TOKEN_VAR}\n{r.stderr}"
