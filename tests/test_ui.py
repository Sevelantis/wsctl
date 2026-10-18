"""ui — the presentation grammar: semantic markup, the one-place palette, and the section/item/summary shape.

The look has to be consistent and safe, so these pin the *contracts* of the grammar itself — not any verb's
wording (that is the behavioural suite's job, and freezing sentences here would only fight it). The contracts:
colour is applied by MEANING through one palette; it strips cleanly when colour is off; markers are quiet glyphs
(✓/✗) with the ⚠️ emoji reserved for a caution; names align into a column whatever the markup; every run can
close on exactly one footer that carries the generic next step only when asked; all of it goes to stderr so
stdout stays data; and markup content is never evaluated — a line of output can never run code.
"""

import re
import subprocess
from pathlib import Path

TOOL = Path(__file__).resolve().parents[1]
ANSI = re.compile(r"\033\[[0-9;]*m")


def _ui(snippet: str, color: str = "1"):
    """Source output.sh + ui.sh with COLOR forced, run the snippet, return (stdout, stderr)."""
    script = f'COLOR={color}; . "{TOOL}/lib/output.sh"; . "{TOOL}/lib/ui.sh"; {snippet}'
    r = subprocess.run(["bash", "-c", script], text=True, capture_output=True)
    assert r.returncode == 0, r.stderr
    return r.stdout, r.stderr


def _plain(s: str) -> str:
    """The visible text — colour codes stripped."""
    return ANSI.sub("", s)


# --- colour is applied by meaning, from one palette ---


def test_markup_colours_by_meaning():
    """A <path> and a <branch> each render in colour, and in DIFFERENT colours — meaning drives the palette."""
    out, _ = _ui('printf "%s" "$(ui_render "<path>a</> <branch>b</>")"')
    assert "\033[" in out, "markup produced no colour with COLOR=1"
    assert _plain(out) == "a b", "markup altered the visible text"
    codes = ANSI.findall(out)
    assert len(set(codes)) >= 2, "path and branch rendered in the same colour — palette not by meaning"


def test_no_color_strips_markup_to_plain_text():
    """With colour off, tags vanish and only the plain text remains — never the literal <tag>."""
    out, _ = _ui('printf "%s" "$(ui_render "laid <path>.mcp.json</> on <branch>main</>")"', color="0")
    assert out == "laid .mcp.json on main", f"not stripped to plain: {out!r}"
    assert "<path>" not in out and "\033[" not in out


def test_unknown_tag_keeps_its_text():
    """An unrecognised tag is left uncoloured but its text still shows — markup never eats content."""
    out, _ = _ui('printf "%s" "$(ui_render "<bogus>keep me</>")"', color="0")
    assert out == "keep me", f"unknown tag dropped or mangled text: {out!r}"


# --- the shared shape: section -> items -> one footer ---


def test_section_items_and_footer_render_the_expected_shape():
    """A section header, status items, and a closing footer appear in order — the one shape every verb uses."""
    _, err = _ui(
        'section "📦" "config"; item ok "<path>.mcp.json</>"; summary "📦" ok "Installed."',
        color="0",
    )
    lines = [ln for ln in err.splitlines() if ln.strip()]
    assert lines[0].endswith("config") and "📦" in lines[0], f"section header wrong: {lines!r}"
    assert lines[1].strip().startswith("✓") and ".mcp.json" in lines[1], f"item wrong: {lines!r}"
    assert lines[-1].startswith("📦") and "Installed." in lines[-1], f"footer wrong: {lines!r}"


def test_markers_are_quiet_glyphs_but_a_caution_is_the_emoji():
    """Successes/failures are quiet glyphs (✓/✗); only a caution uses the ⚠️ emoji, so it alone draws the eye."""
    _, err = _ui('item ok "a"; item warn "b"; item fail "c"', color="0")
    rows = [ln for ln in err.splitlines() if ln.strip()]
    assert "✓" in rows[0] and "⚠" not in rows[0], f"ok row not a quiet glyph: {rows!r}"
    assert "⚠️" in rows[1], f"caution is not the ⚠️ emoji: {rows!r}"
    assert "✗" in rows[2], f"fail row not the ✗ glyph: {rows!r}"


def test_the_footer_carries_the_next_step_only_when_asked():
    """`rebuild` appends the one generic next step verbatim; without it, the footer stays a bare sentence."""
    _, with_tail = _ui('summary "📦" ok "Installed." rebuild', color="0")
    _, no_tail = _ui('summary "📦" ok "All submodules clean."', color="0")
    assert "Rebuild to apply." in with_tail, f"rebuild tail missing: {with_tail!r}"
    assert "Rebuild to apply." not in no_tail, f"rebuild tail leaked onto a footer that didn't ask: {no_tail!r}"


def test_pair_aligns_names_into_a_column():
    """Two names of different length line up: the second column starts at the same place for both rows."""
    _, err = _ui('pair ok ".claude" "on main"; pair ok "devcontainers" "on main"', color="0")
    rows = [ln for ln in err.splitlines() if "on main" in ln]
    assert len(rows) == 2, f"expected two aligned rows: {err!r}"
    assert rows[0].index("on main") == rows[1].index("on main"), f"columns not aligned:\n{rows[0]!r}\n{rows[1]!r}"


# --- the stream rule: the grammar is chatter, never data ---


def test_the_grammar_prints_only_to_stderr():
    """Output is the interface, not data: section/item/summary never touch stdout (which stays pipeable)."""
    out, err = _ui('section "📦" "config"; item ok "x"; summary "📦" ok "done"', color="0")
    assert out == "", f"the grammar leaked to stdout: {out!r}"
    assert err.strip(), "nothing reached stderr"


# --- safety: output can never run code ---


def test_markup_content_is_never_evaluated():
    """A line of output is text, not a command: markup content with $(...) is shown literally, never executed."""
    out, _ = _ui("""printf "%s" "$(ui_render '<path>$(echo PWNED)</>')" """, color="0")
    assert out == "$(echo PWNED)", f"markup content was evaluated: {out!r}"
    assert "PWNED" not in out.replace("$(echo PWNED)", "")
