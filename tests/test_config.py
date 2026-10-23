"""config — provisioning the client skeleton and keeping its version pins current."""

PIN = "example.sample-extension"


def _install(client):
    """Install, and return the path to the seeded client devcontainer.json."""
    client.wsctl("install", check=True)
    return client.path / ".devcontainer" / "devcontainer.json"


# --- keep-current: version pins carried forward ---


def test_update_carries_a_provisioned_pin_forward(client):
    """A provisioned pin left behind the platform is bumped forward on update, never frozen."""
    dc = _install(client)
    dc.write_text(dc.read_text().replace("@1.2.0", "@1.0.0"))
    client.wsctl("update")
    body = dc.read_text()
    assert f"{PIN}@1.2.0" in body
    assert "@1.0.0" not in body


def test_update_leaves_an_equal_pin_untouched(client):
    """A pin already at the platform version is a no-op — no churn, no spurious change."""
    dc = _install(client)
    before = dc.read_text()                       # seeded at the blueprint version (equal)
    client.wsctl("update")
    assert dc.read_text() == before


def test_update_never_downgrades_a_pin_the_client_moved_ahead(client):
    """A client who pinned a newer version keeps it — bump-forward only, never downgrade."""
    dc = _install(client)
    dc.write_text(dc.read_text().replace("@1.2.0", "@2.0.0"))
    client.wsctl("update")
    body = dc.read_text()
    assert f"{PIN}@2.0.0" in body
    assert "@1.2.0" not in body


# --- the client's own edits are respected ---


def test_update_does_not_re_add_a_pin_the_client_removed(client):
    """A provisioned extension the client deleted stays gone — the set is optional to the user."""
    dc = _install(client)
    kept = [ln for ln in dc.read_text().splitlines() if PIN not in ln]
    dc.write_text("\n".join(kept) + "\n")
    client.wsctl("update")
    assert PIN not in dc.read_text()


def test_update_keeps_an_extension_the_client_added(client):
    """A client's own extension is never touched — wsctl only manages the pins it provisions."""
    dc = _install(client)
    dc.write_text(
        dc.read_text().replace(
            '"example.no-version-extension"',
            '"example.no-version-extension",\n    "myteam.custom-tool@9.9.9"',
        )
    )
    client.wsctl("update")
    assert "myteam.custom-tool@9.9.9" in dc.read_text()


def test_update_leaves_a_version_less_pin_alone(client):
    """An extension pinned with no version is skipped, never mangled."""
    dc = _install(client)
    client.wsctl("update")
    assert '"example.no-version-extension"' in dc.read_text()


# --- fail-safe: never corrupt a file it cannot cleanly match ---


def test_update_skips_a_reformatted_pin_without_corrupting_the_file(client):
    """A pin the client re-quoted or reshaped is left exactly as is — skip over corrupt."""
    dc = _install(client)
    reshaped = dc.read_text().replace(
        '"example.sample-extension@1.2.0"',
        "'example.sample-extension@1.0.0'",       # single-quoted: no exact match to replace
    )
    dc.write_text(reshaped)
    client.wsctl("update")
    assert dc.read_text() == reshaped             # byte-identical: untouched, uncorrupted


def test_update_does_not_touch_a_file_outside_the_manifest(client):
    """Only files the manifest manages are written — a client-owned file is never modified."""
    _install(client)
    own = client.path / "my-notes.txt"
    own.write_text("client-owned, not managed\n")
    client.wsctl("update")
    assert own.read_text() == "client-owned, not managed\n"


# --- coverage: multiple pins, --force, and a missing managed file ---


def test_update_bumps_multiple_pins_in_one_pass(client):
    """More than one provisioned pin behind the platform is carried forward in a single update."""
    dc = _install(client)
    dc.write_text(dc.read_text().replace("@1.2.0", "@1.0.0").replace("@3.4.0", "@3.0.0"))
    client.wsctl("update")
    out = dc.read_text()
    assert "example.sample-extension@1.2.0" in out and "example.other-tool@3.4.0" in out
    assert "@1.0.0" not in out and "@3.0.0" not in out


def test_install_force_restores_a_modified_seed_only_file(client):
    """install --force re-scaffolds a seed-only file the client changed, back to the platform default."""
    _install(client)
    npmrc = client.path / ".npmrc"
    npmrc.write_text("tampered\n")
    client.wsctl("install", "--force", check=True)
    assert "tampered" not in npmrc.read_text(), "--force did not overwrite the modified seed-only file"


def test_update_advises_install_when_a_managed_file_is_missing(client):
    """If a keep-current file is gone, update advises running install — it never re-seeds or crashes."""
    dc = _install(client)
    dc.unlink()
    r = client.wsctl("update")
    assert not dc.exists(), "update re-seeded a keep-current file in sync mode"
    assert "install" in (r.stdout + r.stderr).lower(), "update did not advise running install"


# --- fail-safe: a commented-out pin must not be mistaken for the live one ---


def test_update_ignores_a_pin_inside_a_jsonc_comment(client):
    """A stale pin left in a // comment must not be read or rewritten — only the live array pin is bumped."""
    dc = _install(client)
    dc.write_text(
        dc.read_text().replace(
            '"example.sample-extension@1.2.0"',
            '// "example.sample-extension@0.9.0"\n    "example.sample-extension@1.0.0"',
        )
    )
    client.wsctl("update")
    out = dc.read_text()
    assert '"example.sample-extension@1.2.0"' in out, "the live pin was not bumped forward"
    assert "@1.0.0" not in out, "the live pin kept its old version"
    assert "@0.9.0" in out, "the commented-out pin was rewritten"


# --- hardening: odd-but-real file shapes (bash + standard tools, no jq) ---


def test_update_handles_windows_line_endings(client):
    """A devcontainer.json saved with CRLF (WSL clients) still bumps correctly and stays CRLF."""
    dc = _install(client)
    dc.write_bytes(dc.read_text().replace("@1.2.0", "@1.0.0").replace("\n", "\r\n").encode())
    client.wsctl("update")
    raw = dc.read_bytes()
    assert b"example.sample-extension@1.2.0" in raw, "CRLF file was not bumped"
    assert b"\r\n" in raw, "CRLF line endings were lost"


def test_update_ignores_a_lookalike_token_embedded_in_another_value(client):
    """An id@version embedded in a longer string (not a standalone quoted pin) is never rewritten — quote-anchored."""
    dc = _install(client)
    body = dc.read_text().replace("@1.2.0", "@1.0.0").replace(
        '"customizations"',
        '"postCreateCommand": "install example.sample-extension@1.0.0 now",\n  "customizations"',
    )
    dc.write_text(body)
    client.wsctl("update")
    out = dc.read_text()
    assert "install example.sample-extension@1.0.0 now" in out, "an embedded look-alike token was wrongly rewritten"
    assert '"example.sample-extension@1.2.0"' in out, "the real pin was not bumped"


def test_update_never_rewrites_a_same_version_pin_in_a_comment(client):
    """A // comment holding the exact live version must be left intact — comments are never edited."""
    dc = _install(client)
    dc.write_text(
        dc.read_text().replace(
            '"example.sample-extension@1.2.0"',
            '// pinned at "example.sample-extension@1.0.0" once\n    "example.sample-extension@1.0.0"',
        )
    )
    client.wsctl("update")
    out = dc.read_text()
    assert '// pinned at "example.sample-extension@1.0.0" once' in out, "the comment was rewritten"
    assert out.count("example.sample-extension@1.2.0") == 1, "the bump leaked into the comment"


def test_update_survives_a_prerelease_version_string(client):
    """A pre-release version (e.g. 1.0.0-beta) must not crash the bump; it is compared by its numeric segments."""
    dc = _install(client)
    dc.write_text(
        dc.read_text().replace("example.sample-extension@1.2.0", "example.sample-extension@1.0.0-beta")
    )
    r = client.wsctl("update")
    assert r.returncode == 0, f"update crashed on a pre-release pin\n{r.stderr}"
    assert "example.sample-extension@1.2.0" in dc.read_text(), "pre-release pin not bumped forward"


def test_update_bumps_a_duplicated_pin_consistently(client):
    """The same extension listed twice at the same version is bumped on every occurrence, never half-done."""
    dc = _install(client)
    dc.write_text(
        dc.read_text().replace(
            '"example.sample-extension@1.2.0",',
            '"example.sample-extension@1.0.0",\n    "example.sample-extension@1.0.0",',
        )
    )
    client.wsctl("update")
    out = dc.read_text()
    assert "@1.0.0" not in out, "a duplicated pin was only half-bumped"
    assert out.count("example.sample-extension@1.2.0") == 2, "not all duplicates were bumped"
