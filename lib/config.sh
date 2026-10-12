# config — the managed submodules, their clone URLs (+ an offline-test seam), and template provisioning.

SUBMODULES=".claude devcontainers"      # the two platform submodules this project syncs (single source of truth)
DEFAULT_BRANCH="master"                  # the branch submodules float on
TOKEN_VAR="GH_TOKEN_RO_INFRA"            # the read-only key, read from .env at point-of-use
GH_MATCH="https://github.com/"           # URL-scope for the token header (never bare — only github.com sees it)
GIT_MIN="2.31"                           # GIT_CONFIG_COUNT support floor

valid_submodule() { local x; for x in $SUBMODULES; do [ "$x" = "$1" ] && return 0; done; return 1; }

# url_for <name> — the clone URL. WSCTL_REMOTE_BASE redirects to local bare repos for offline tests
# (the only test seam; unset = production). It changes only the address, so the tested path is the shipped path.
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

# provision_config [--force] — lay client config from templates/ into the project root. Idempotent:
# never clobbers an existing file unless --force. Picks up whatever lives in templates/ (incl. dotfiles).
provision_config() {
  local force="${1:-}" t name dest laid=0
  shopt -s nullglob dotglob
  for t in "$WSCTL_HOME"/templates/*; do
    [ -f "$t" ] || continue                       # only regular files are config blueprints — skip stray dirs/caches
    name="$(basename -- "$t")"; dest="$ROOT/$name"
    if [ -e "$dest" ] && [ "$force" != "--force" ]; then log "  config: $name present (keep)"; continue; fi
    cp -- "$t" "$dest"; ok "  config: $name"; laid=$((laid + 1))
  done
  shopt -u nullglob dotglob
  [ "$laid" -gt 0 ] || log "  config: all present"
}
