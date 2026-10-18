# ui — the presentation grammar on top of output.sh. One shape for every verb: an emoji-led section, aligned
# items beneath it, and one closing footer. Colour means something — a call site tags WHAT a word is
# (<path>, <branch>, <cmd> …) and the palette below decides the colour, so the look cannot drift. Everything
# goes to stderr (the stream rule: stdout stays data); colour strips to plain when --no-color is set or output
# is not a terminal (output.sh already resolved COLOR for us, keyed on stderr).

# The palette — one place maps a meaning to a colour. Change it here and the whole tool follows.
if [ "${COLOR:-0}" = 0 ]; then
  C_PATH=""; C_BRANCH=""; C_CMD=""; C_OK=""; C_WARN=""; C_ERR=""; C_LABEL=""
else
  C_PATH=$'\033[90m'        # grey   — paths and filenames
  C_BRANCH=$'\033[36m'      # cyan   — branch names
  C_CMD=$'\033[32m'         # green  — commands the user can run
  C_OK=$'\033[32m'          # green  — success
  C_WARN=$'\033[33m'        # yellow — a caution
  C_ERR=$'\033[31m'         # red    — an error
  C_LABEL=$'\033[38;5;100m' # olive  — section labels
fi

# ui_render <text> — resolve <tag>…</> spans to their palette colour. Non-nested, left to right; an unknown tag
# is left uncoloured (the text still shows). With colour off, the tags simply vanish and plain text remains.
# The content is only ever printed, never evaluated — a line of output can never run code.
ui_render() {
  local s="$1" pre rest tag content color
  while :; do
    case "$s" in *'<'*'>'*'</>'*) ;; *) break ;; esac
    pre="${s%%<*}"; rest="${s#*<}"
    tag="${rest%%>*}"; rest="${rest#*>}"
    content="${rest%%</>*}"; rest="${rest#*</>}"
    case "$tag" in
      path)   color="$C_PATH" ;;   branch) color="$C_BRANCH" ;; cmd) color="$C_CMD" ;;
      ok)     color="$C_OK" ;;     warn)   color="$C_WARN" ;;   error) color="$C_ERR" ;;
      label)  color="$C_LABEL" ;;  *)      color="" ;;
    esac
    s="${pre}${color}${content}${C_RST}${rest}"
  done
  printf '%s' "$s"
}

# ui_width <text> — the visible width of rendered text, ignoring colour codes, so columns line up whatever the
# markup. Local and stateless: no counter, no shared file.
ui_width() {
  local plain; plain="$(printf '%s' "$1" | sed $'s/\033\\[[0-9;]*m//g')"
  printf '%s' "${#plain}"
}

# ui_mark <ok|warn|fail> — the status marker, in a fixed-width cell so item and pair columns align whatever the
# marker: ✓/✗ are one column (padded to three), the ⚠️ caution emoji is two (padded to three). Successes are
# quiet glyphs; a caution is the emoji so it alone catches the eye.
ui_mark() {
  case "$1" in
    ok)   printf '%s✓%s  ' "$C_OK" "$C_RST" ;;
    warn) printf '⚠️ ' ;;
    fail) printf '%s✗%s  ' "$C_ERR" "$C_RST" ;;
    *)    printf '   ' ;;
  esac
}

# section <emoji> <label> — open a group: the emoji then the olive (rendered) label. Dense: no blank line before.
section() { printf '%s %s%s%s\n' "$1" "$C_LABEL" "$(ui_render "$2")" "$C_RST" >&2; }

# item <ok|warn|fail> <text> — an indented status line under a section.
item() { local m; m="$(ui_mark "$1")"; shift; printf '  %s%s\n' "$m" "$(ui_render "$*")" >&2; }

# pair <ok|warn|fail> <name> <rest> — like item, but <name> is padded to UI_PAD so names line up in a column
# within a section (e.g. the two submodules). Padding uses the visible width, so markup never skews it.
UI_PAD="${UI_PAD:-14}"
pair() {
  local m name pad; m="$(ui_mark "$1")"; name="$(ui_render "$2")"; shift 2
  pad=$(( UI_PAD - $(ui_width "$name") )); [ "$pad" -lt 0 ] && pad=0
  printf '  %s%s%*s%s\n' "$m" "$name" "$pad" "" "$(ui_render "$*")" >&2
}

# cmdlog <text> — a failed subcommand's OWN output, captured and indented, dim. Shown so a break is observable,
# never raw and never on stdout.
cmdlog() { printf '      %s%s%s\n' "$C_DIM" "$*" "$C_RST" >&2; }

# fix <text> — a single next step, dim, and ONLY when the next action is wsctl's job (never for what isn't ours).
fix() { printf '    %s→ %s%s\n' "$C_DIM" "$(ui_render "$*")" "$C_RST" >&2; }

# ui_rule — the dim hairline that sits just before a closing line (dense separation). Part of the grammar's
# public surface: `summary` draws it, and `docker` reuses it beneath its own chart.
ui_rule() { printf '  %s──────%s\n' "$C_DIM" "$C_RST" >&2; }

# summary <verb-emoji> <ok|warn|fail> <sentence> [rebuild] — the one closing line every verb ends on, on every
# state (success AND failure): the verb's emoji, then a short coloured sentence. Pass `rebuild` to append the
# single generic next step, verbatim, where a rebuild applies.
summary() {
  local emoji="$1" kind="$2" sentence="$3" col="" tail=""
  case "$kind" in ok) col="$C_OK" ;; warn) col="$C_WARN" ;; fail) col="$C_ERR" ;; esac
  [ "${4:-}" = rebuild ] && tail=" ${C_DIM}Rebuild to apply.${C_RST}"
  ui_rule
  printf '%s %s%s%s%s\n' "$emoji" "$col" "$(ui_render "$sentence")" "$C_RST" "$tail" >&2
}
