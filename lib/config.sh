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

# provision_config — copy templates/ into the project; keeps existing files unless --force.
# A template's path relative to templates/ is its destination under $ROOT, e.g.:
#   templates/.mcp.json                            → $ROOT/.mcp.json
#   templates/.devcontainer/docker-compose.client.yaml → $ROOT/.devcontainer/docker-compose.client.yaml
# Prints one item per file — a present file reads the same as a freshly laid one, because from the user's side
# the outcome is identical: the config is in place. The verb prints the section header around this.
provision_config() {
  local force="${1:-}" t rel dest
  while IFS= read -r t; do
    rel="${t#"$WSCTL_HOME"/templates/}"           # path relative to templates/ = destination relative to $ROOT
    dest="$ROOT/$rel"
    if [ -e "$dest" ] && [ "$force" != "--force" ]; then
      item ok "<path>$(basename -- "$rel")</>"    # already present — keep it
    else
      mkdir -p -- "$(dirname -- "$dest")"
      cp -- "$t" "$dest"; item ok "<path>$(basename -- "$rel")</>"
    fi
  done < <(find "$WSCTL_HOME/templates" -type f)
}
