"""root resolution — wsctl must act on the PROJECT root no matter which directory it is run from.

With no `wsctl` command installed yet, a client runs the tool by its path, often `cd .wsctl` first and then
`bash wsctl.sh <verb>`. The project root must come from where the tool is installed (<project>/.wsctl), never
from $PWD — otherwise the token (.env) and the managed submodules are read from, and written to, the wrong
place. These guard two findings seen on a real client: the token looked for in .wsctl/.env instead of the
project root, and reset leaving the project-root submodules in place.
"""

import shutil
import subprocess
from pathlib import Path

TOOL = Path(__file__).resolve().parents[1]      # the wsctl/ checkout under test
SUBMODULES = (".claude", "devcontainers")


def _deploy(repo: Path) -> Path:
    """Lay the tool out the way a real client has it: cloned into <project>/.wsctl/."""
    wsctl_dir = repo / ".wsctl"
    wsctl_dir.mkdir()
    for item in ("wsctl.sh", "lib", "templates"):
        src = TOOL / item
        (shutil.copytree if src.is_dir() else shutil.copy2)(src, wsctl_dir / item)
    return wsctl_dir


def _run(tool: Path, cwd: Path, env: dict, *args):
    return subprocess.run(
        ["bash", str(tool), *args], cwd=str(cwd), env=env, text=True, capture_output=True
    )


def test_install_from_inside_launcher_dir_finds_project_root_env(client):
    """`cd .wsctl && wsctl install` must read the token from the project-root .env, not .wsctl/.env."""
    wsctl_dir = _deploy(client.path)
    r = _run(wsctl_dir / "wsctl.sh", wsctl_dir, client.env, "install")
    assert "is not set" not in r.stderr, f"token looked for in the wrong .env\n{r.stderr}"
    assert r.returncode == 0, f"install failed when run from inside .wsctl/\n{r.stderr}"
    for s in SUBMODULES:
        assert (client.path / s / ".git").exists(), f"{s} not provisioned at the project root"
        assert not (wsctl_dir / s).exists(), f"{s} wrongly placed inside .wsctl/"


def test_reset_from_inside_launcher_dir_cleans_project_root_submodules(client):
    """reset run from inside .wsctl/ must remove the project-root submodules, not look inside .wsctl/."""
    wsctl_dir = _deploy(client.path)
    assert _run(wsctl_dir / "wsctl.sh", client.path, client.env, "install").returncode == 0
    r = _run(wsctl_dir / "wsctl.sh", wsctl_dir, client.env, "reset")
    assert r.returncode == 0, f"reset failed\n{r.stderr}"
    for s in SUBMODULES:
        assert not (client.path / s).exists(), f"{s} survived reset run from inside .wsctl/"


def test_install_from_project_root_still_works_in_the_deployed_layout(client):
    """The one-liner runs `.wsctl/wsctl.sh install` from the project root — that must keep working."""
    wsctl_dir = _deploy(client.path)
    r = _run(wsctl_dir / "wsctl.sh", client.path, client.env, "install")
    assert r.returncode == 0, r.stderr
    for s in SUBMODULES:
        assert (client.path / s / ".git").exists(), f"{s} not provisioned at the project root"
