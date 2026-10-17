# drift — the read-only checks behind `health`; they report problems and never change anything.

# health_report — print one line per check (pass or fail) to stderr; return 1 if any failed, else 0.
health_report() {
  local s rc=0
  for s in $SUBMODULES; do
    if [ ! -e "$ROOT/$s/.git" ]; then
      warn "$s — not present (re-clone with the read-only key, or run 'reinstall')"; rc=1
    elif ! git -C "$ROOT/$s" symbolic-ref -q HEAD >/dev/null 2>&1; then
      warn "$s — detached HEAD, no branch to float (checkout a branch, then 'update')"; rc=1
    else
      ok "$s — present, on $(current_branch "$s")"
    fi
  done
  if vis_exclude_applied; then
    ok "hidden — .git/info/exclude hides the platform folders"
  else
    warn "hidden — .git/info/exclude is missing wsctl entries, folders not hidden (run 'reinstall')"; rc=1
  fi
  return "$rc"
}
