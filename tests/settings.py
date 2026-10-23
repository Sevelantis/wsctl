"""settings — the single source for the test suite's fixtures: submodules, dummy content, the client skeleton.

Every value has a default, so the suite runs with zero configuration; pydantic lets any of them be overridden
from WSCTL_TEST_* environment variables the day parameterization is needed. Clients never run the tests, so
pydantic is a dev-only dependency with no client cost.
"""

from pydantic import BaseModel
from pydantic_settings import BaseSettings, SettingsConfigDict

# The dummy devcontainer blueprint the tests provision: two versioned pins + one version-less entry.
_DEVCONTAINER_BLUEPRINT = (
    "{\n"
    '  "customizations": { "vscode": { "extensions": [\n'
    '    "example.sample-extension@1.2.0",\n'
    '    "example.other-tool@3.4.0",\n'
    '    "example.no-version-extension"\n'
    "  ] } }\n"
    "}\n"
)


class Blueprint(BaseModel):
    """One file the dummy client skeleton provisions: its skeleton filename, content, destination, and policy."""

    name: str
    content: str
    dest: str
    policy: str  # seed-only | keep-current


class TestSettings(BaseSettings):
    """Static test fixtures; each field has a default, overridable via a WSCTL_TEST_* env var if ever needed."""

    model_config = SettingsConfigDict(env_prefix="WSCTL_TEST_")

    submodules: tuple[str, ...] = (".claude", "devcontainers")
    dummy_files: dict[str, str] = {".claude": "abc.txt", "devcontainers": "xyz.txt"}
    dummy_token: str = "github_pat_DUMMY_0000000000000000000000"
    skeleton: list[Blueprint] = [
        Blueprint(name="devcontainer-default.json", content=_DEVCONTAINER_BLUEPRINT,
                  dest=".devcontainer/devcontainer.json", policy="keep-current"),
        Blueprint(name=".mcp.json", content="{}\n", dest=".mcp.json", policy="seed-only"),
        Blueprint(name=".npmrc", content="# npm settings\n", dest=".npmrc", policy="seed-only"),
        Blueprint(name="docker-compose.client.yaml", content="services: {}\n",
                  dest=".devcontainer/docker-compose.client.yaml", policy="seed-only"),
    ]

    @property
    def manifest_text(self) -> str:
        """The provision.list the dummy devcontainers remote carries — one row per blueprint."""
        return "".join(f"{b.name}   {b.dest}   {b.policy}\n" for b in self.skeleton)

    @property
    def skeleton_dests(self) -> tuple[str, ...]:
        """Every destination the skeleton provisions — for 'install laid them all' assertions."""
        return tuple(b.dest for b in self.skeleton)

    @property
    def shared_files(self) -> tuple[str, ...]:
        """Client-owned files reset/reinstall must never remove: the seeded (seed-only) configs plus .env."""
        return tuple(b.dest for b in self.skeleton if b.policy == "seed-only") + (".env",)


settings = TestSettings()

# Convenience module constants, so a test reads `from settings import SUBMODULES` with no behaviour change.
SUBMODULES = settings.submodules
DUMMY_FILE = settings.dummy_files
DUMMY_TOKEN = settings.dummy_token
SHARED = settings.shared_files
