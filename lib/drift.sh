# drift — the read-only checks behind `health`; they report problems and never change anything.

# health_report — print one item per check to stderr, and tally what it found. Returns 1 if any check failed,
# else 0 (the verb's exit contract). Two counts are left for the caller to phrase the footer with: HEALTH_MISSING
# (submodules not cloned) and HEALTH_ISSUES (every problem — missing, detached, or no longer hidden).
health_report() {
  local s rc=0
  HEALTH_MISSING=0; HEALTH_ISSUES=0
  for s in $SUBMODULES; do
    if [ ! -e "$ROOT/$s/.git" ]; then
      item fail "<path>$s</> not cloned"; HEALTH_MISSING=$((HEALTH_MISSING + 1)); HEALTH_ISSUES=$((HEALTH_ISSUES + 1)); rc=1
    elif ! git -C "$ROOT/$s" symbolic-ref -q HEAD >/dev/null 2>&1; then
      item warn "<path>$s</> detached — no branch to float"; HEALTH_ISSUES=$((HEALTH_ISSUES + 1)); rc=1
    else
      item ok "<path>$s</> present, on <branch>$(current_branch "$s")</>"
    fi
  done
  if vis_exclude_applied; then
    item ok "hidden from <cmd>git status</>"
  else
    item warn "no longer hidden from <cmd>git status</>"; HEALTH_ISSUES=$((HEALTH_ISSUES + 1)); rc=1
  fi
  return "$rc"
}
