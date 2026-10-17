# visibility — invisible-mode provisioning: the two managed submodules as PLAIN clones hidden by
# local .git/info/exclude. No committed pin, no .gitmodules, nothing stageable — structurally immune
# to the F1–F6 class (→ visibility.md). Opt-in for now (`setup --invisible`); the design default later.

EXCLUDE_BEGIN="# wsctl-invisible-begin"
EXCLUDE_END="# wsctl-invisible-end"

# vis_apply_exclude — idempotently fence the managed submodules into .git/info/exclude. Per-clone
# (lives in .git/, never committed, never pushed); re-applied every run so a fresh clone self-heals.
vis_apply_exclude() {
  local f="$ROOT/.git/info/exclude" s
  git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || return 0
  mkdir -p "$ROOT/.git/info"
  [ -f "$f" ] && { sed "/$EXCLUDE_BEGIN/,/$EXCLUDE_END/d" "$f" > "$f.tmp" && mv "$f.tmp" "$f"; }
  { printf '%s\n' "$EXCLUDE_BEGIN"; for s in $SUBMODULES; do printf '/%s/\n' "$s"; done; printf '%s\n' "$EXCLUDE_END"; } >> "$f"
}

# vis_exclude_applied — true when .git/info/exclude carries wsctl's entry for EVERY managed submodule
# (what `health` reads to know the submodules are still hidden). Read-only.
vis_exclude_applied() {
  local f="$ROOT/.git/info/exclude" s
  [ -f "$f" ] || return 1
  for s in $SUBMODULES; do grep -qxF "/$s/" "$f" 2>/dev/null || return 1; done
  return 0
}

# vis_remove_exclude — strip wsctl's fenced block from .git/info/exclude (used by `reset`, so a fresh
# `install` re-applies it clean). Idempotent: a no-op when the block/file is absent.
vis_remove_exclude() {
  local f="$ROOT/.git/info/exclude"
  [ -f "$f" ] || return 0
  sed "/$EXCLUDE_BEGIN/,/$EXCLUDE_END/d" "$f" > "$f.tmp" && mv "$f.tmp" "$f"
}

# provision_invisible <token> — clone (or float) each managed submodule as a plain clone, then hide it.
# Never touches submodule machinery (add/pin/.gitmodules/ignore) — that's normal mode's job.
provision_invisible() {
  local tok="$1" rc=0 s out
  info "→ ensuring submodules (invisible) …"
  for s in $SUBMODULES; do
    if [ -e "$ROOT/$s/.git" ]; then
      discard_dirty "$s"; ensure_on_branch "$s"          # float on the checked-out branch; re-run safe
      log "  $s: present — on $(current_branch "$s") (float)"
    elif out="$(git_ro "$tok" -C "$ROOT" clone --quiet --branch "$DEFAULT_BRANCH" "$(url_for "$s")" "$s" 2>&1)"; then
      ensure_on_branch "$s"
      ok "  $s: cloned (on $(current_branch "$s"))"
    else
      printf '%s\n' "$out" | sed 's/^/      /' >&2
      warn "  $s: clone FAILED — check $TOKEN_VAR has Contents:Read on $(url_for "$s")"; rc=1
    fi
  done
  vis_apply_exclude                                       # hide them from the parent (per-clone, zero committed trace)
  return $rc
}

# provision_normal — PARKED (stopped 2026-10-15 to unblock development; may return). Normal mode = standard
# committed submodules (pins + .gitmodules + submodule.<name>.ignore=all). It was cut because it carries the
# entire F1–F6 bug class that invisible mode is structurally immune to (→ known-issues.md). This stub is the
# reserved seam: to revive, implement the submodule add/update + set_ignore_local path here (the helpers still
# live in lib/git.sh) and wire the `normal` arm of WSCTL_MODE in cmd_install.
# provision_normal() { ... }   # intentionally not implemented
