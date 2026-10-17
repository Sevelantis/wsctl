# visibility — clones the managed submodules as plain repos and hides them via .git/info/exclude (nothing to commit).

EXCLUDE_BEGIN="# wsctl-invisible-begin"
EXCLUDE_END="# wsctl-invisible-end"

# vis_apply_exclude — add the submodules and launcher dir to .git/info/exclude in a marked block (safe to re-run).
# The file is local to this clone, so nothing is committed or pushed.
vis_apply_exclude() {
  local f="$ROOT/.git/info/exclude" s
  git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || return 0
  mkdir -p "$ROOT/.git/info"
  [ -f "$f" ] && { sed "/$EXCLUDE_BEGIN/,/$EXCLUDE_END/d" "$f" > "$f.tmp" && mv "$f.tmp" "$f"; }
  {
    printf '%s\n' "$EXCLUDE_BEGIN"
    for s in $SUBMODULES; do printf '/%s/\n' "$s"; done
    printf '/%s/\n' "$WSCTL_DIR"
    printf '%s\n' "$EXCLUDE_END"
  } >> "$f"
}

# vis_exclude_applied — true when .git/info/exclude lists every managed submodule and the launcher dir. Read-only.
vis_exclude_applied() {
  local f="$ROOT/.git/info/exclude" s
  [ -f "$f" ] || return 1
  for s in $SUBMODULES; do grep -qxF "/$s/" "$f" 2>/dev/null || return 1; done
  grep -qxF "/$WSCTL_DIR/" "$f" 2>/dev/null || return 1
  return 0
}

# vis_remove_exclude — delete wsctl's block from .git/info/exclude (used by `reset`); no-op if absent.
vis_remove_exclude() {
  local f="$ROOT/.git/info/exclude"
  [ -f "$f" ] || return 0
  sed "/$EXCLUDE_BEGIN/,/$EXCLUDE_END/d" "$f" > "$f.tmp" && mv "$f.tmp" "$f"
}

# provision_invisible <token> — clone each managed submodule (or keep the existing one current), then hide it.
provision_invisible() {
  local tok="$1" rc=0 s out
  info "→ ensuring submodules (invisible) …"
  for s in $SUBMODULES; do
    if [ -e "$ROOT/$s/.git" ]; then
      discard_dirty "$s"; ensure_on_branch "$s"          # float on the checked-out branch; re-run safe
      log "  $s: present — on $(current_branch "$s") (float)"
      continue
    fi
    info "  → cloning $s …"                               # narrate the slow step so it never looks hung
    debug "clone $(url_for "$s") → $ROOT/$s (branch $DEFAULT_BRANCH)"   # the command, minus the token (injected via env)
    if out="$(git_ro "$tok" -C "$ROOT" clone --quiet --branch "$DEFAULT_BRANCH" "$(url_for "$s")" "$s" 2>&1)"; then
      ensure_on_branch "$s"
      ok "  $s: cloned (on $(current_branch "$s"))"
    else
      printf '%s\n' "$out" | sed 's/^/      /' >&2
      warn "  $s: clone FAILED — check $TOKEN_VAR has Contents:Read on $(url_for "$s")"; rc=1
    fi
  done
  vis_apply_exclude                                       # hide them from the parent (local to this clone, nothing committed)
  return $rc
}

# provision_normal — reserved placeholder for a future standard-submodule mode; intentionally not implemented.
# provision_normal() { ... }
