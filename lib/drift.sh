# drift — the read-only drift enumerator behind `health`: reports what's wrong, changes nothing.
# Invisible-mode scope (the only mode): each managed submodule must be PRESENT and ON ITS BRANCH, and the
# hide-exclude must be applied. Freshness ("behind the center?") is out of scope here (needs network + key).
# Keyless and read-only: it never clones, pulls, or writes. Echoes ONE deviation per line, tab-separated as
#   <code>\t<target>\t<human message>
# and prints nothing at all when the workspace is at target. Codes: missing | detached | exclude.

drift_enumerate() {
  local s
  for s in $SUBMODULES; do
    if [ ! -e "$ROOT/$s/.git" ]; then
      printf 'missing\t%s\t%s not present (needs re-clone with the RO key)\n' "$s" "$s"
    elif ! git -C "$ROOT/$s" symbolic-ref -q HEAD >/dev/null 2>&1; then
      printf 'detached\t%s\t%s is detached — no branch to float\n' "$s" "$s"
    fi
  done
  vis_exclude_applied || printf 'exclude\t-\t.git/info/exclude is missing wsctl entries — submodules not hidden\n'
}
