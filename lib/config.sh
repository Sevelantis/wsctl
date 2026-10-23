# config — the managed submodules, their clone URLs, and template provisioning.

SUBMODULES=".claude devcontainers"      # the two platform submodules this project syncs (single source of truth)
WSCTL_DIR=".wsctl"                       # the launcher dir (the clone target) — hidden in invisible mode like the submodules
DEFAULT_BRANCH="master"                  # the branch submodules float on
TOKEN_VAR="GH_TOKEN_RO_INFRA"            # the read-only key, read from .env at point-of-use
GH_MATCH="https://github.com/"           # URL-scope for the token header (never bare — only github.com sees it)
GIT_MIN="2.31"                           # GIT_CONFIG_COUNT support floor

# Visibility mode. invisible (supported): plain clones hidden via .git/info/exclude, with no committed pin
# and no .gitmodules. normal (standard committed submodules): reserved, not implemented.
WSCTL_MODE="${WSCTL_MODE:-invisible}"     # invisible (supported) | normal (reserved)

# valid_submodule <name> — true when <name> is one of the managed submodules.
valid_submodule() { local x; for x in $SUBMODULES; do [ "$x" = "$1" ] && return 0; done; return 1; }

# url_for <name> — the clone URL. Setting WSCTL_REMOTE_BASE points clones at local bare repos for offline
# tests; it changes only the address, so tests run the same code path as production.
url_for() {
  if [ -n "${WSCTL_REMOTE_BASE:-}" ]; then
    valid_submodule "$1" && { printf '%s/%s.git' "${WSCTL_REMOTE_BASE%/}" "$1"; return 0; }
    return 1
  fi
  case "$1" in
    .claude)       printf 'https://github.com/Sevelantis/.claude.git' ;;
    devcontainers) printf 'https://github.com/Sevelantis/devcontainers.git' ;;
    *) return 1 ;;
  esac
}

# --- managed config from the client skeleton (manifest-driven) ---
# The devcontainers submodule carries a client skeleton: blueprint files plus a manifest that maps each
# blueprint to its destination in the project and how to keep it current. wsctl renders from that skeleton
# once the submodule is present, so the platform owns what ships and clients never hand-edit versions.
SKELETON_SUBMODULE="devcontainers"       # the submodule that carries the skeleton
SKELETON_REL=".devcontainer/client"      # the skeleton path within it (blueprints + manifest)

# skeleton_dir — the absolute path of the client skeleton inside the pulled submodule.
skeleton_dir() { printf '%s/%s/%s' "$ROOT" "$SKELETON_SUBMODULE" "$SKELETON_REL"; }

# extract_pins <file> — print each "<id>@<version>" pin in the file, one "id@version" per line.
extract_pins() {
  grep -oE '"[A-Za-z0-9][A-Za-z0-9._-]*@[0-9][0-9A-Za-z.+-]*"' "$1" 2>/dev/null | tr -d '"' || true
}

# pin_version <file> <id> — print the version <id> is pinned at in the file, or nothing if it is not pinned.
# Full-line // comments are skipped first, so a commented-out pin can never be read as the live one.
pin_version() {
  local id_re; id_re="$(printf '%s' "$2" | sed 's/[.[*^$\\]/\\&/g')"
  grep -v '^[[:space:]]*//' "$1" 2>/dev/null | grep -oE "\"${id_re}@[0-9][0-9A-Za-z.+-]*\"" | head -n1 | sed -E 's/.*@//; s/"$//' || true
}

# replace_pin <file> <id> <old> <new> — replace the exact "<id>@<old>" with "<id>@<new>" in place, atomically.
# Full-line // comments are skipped, so a pin left in a comment is never rewritten. Writes to a temp copy and
# swaps only on success, so the file is never left half-written.
replace_pin() {
  local f="$1" id="$2" old="$3" new="$4" eid eold tmp
  eid="$(printf '%s' "$id" | sed 's/[.[*^$\\]/\\&/g')"
  eold="$(printf '%s' "$old" | sed 's/[.[*^$\\]/\\&/g')"
  tmp="$(mktemp "${f}.wsctl.XXXXXX")" || return 1
  if sed "/^[[:space:]]*\/\//!s|\"${eid}@${eold}\"|\"${id}@${new}\"|g" "$f" > "$tmp" 2>/dev/null; then
    mv -- "$tmp" "$f"
  else
    rm -f -- "$tmp"; return 1
  fi
}

# bump_pins <blueprint> <dest> <label> — carry each version pin in dest forward to the blueprint's newer one.
# Forward only (never downgrade a client who went ahead); a pin dest does not carry is left alone.
bump_pins() {
  local bp="$1" dst="$2" label="$3" id new old bumped=0
  while IFS='@' read -r id new; do
    [ -n "$id" ] && [ -n "$new" ] || continue
    old="$(pin_version "$dst" "$id")"
    [ -n "$old" ] || continue                         # dest does not pin this id — skip, never re-add
    [ "$old" = "$new" ] && continue                   # already current
    version_ge "$new" "$old" || continue              # forward only
    replace_pin "$dst" "$id" "$old" "$new" && { item ok "<path>$id</> <branch>$old</> → <branch>$new</>"; bumped=$((bumped + 1)); }
  done < <(extract_pins "$bp")
  [ "$bumped" -gt 0 ] || item ok "<path>$label</> up to date"
}

# render_seed <blueprint> <dest> <label> [--force] — lay the blueprint at dest if absent; keep an existing file
# untouched unless --force overwrites it (re-scaffold to the platform default).
render_seed() {
  local bp="$1" dst="$2" label="$3" force="${4:-}"
  if [ -e "$dst" ] && [ "$force" != "--force" ]; then item ok "<path>$label</>"; return 0; fi
  mkdir -p -- "$(dirname -- "$dst")"; cp -- "$bp" "$dst"; item ok "<path>$label</>"
}

# provision_managed <seed|sync> — render each managed file per the skeleton manifest. seed (install) lays files
# and bumps; sync (update) bumps the files already present and never seeds. Quiet no-op until the skeleton exists.
provision_managed() {
  local mode="${1:-seed}" force="${2:-}" sk manifest blueprint dest policy bp dst
  sk="$(skeleton_dir)"; manifest="$sk/provision.list"
  [ -f "$manifest" ] || return 0
  while read -r blueprint dest policy; do
    case "$blueprint" in ''|'#'*) continue ;; esac
    [ -n "$dest" ] && [ -n "$policy" ] || continue
    bp="$sk/$blueprint"; dst="$ROOT/$dest"
    [ -f "$bp" ] || { item warn "<path>$dest</> blueprint missing"; continue; }
    case "$policy" in
      seed-only)    if [ "$mode" = seed ]; then render_seed "$bp" "$dst" "$dest" "$force"; fi ;;
      keep-current)
        if [ -e "$dst" ]; then bump_pins "$bp" "$dst" "$dest"
        elif [ "$mode" = seed ]; then render_seed "$bp" "$dst" "$dest" "$force"
        else item warn "<path>$dest</> not found — run <cmd>wsctl install</>"; fi ;;
      *) item warn "<path>$dest</> unknown policy '$policy'" ;;
    esac
  done < "$manifest"
}
