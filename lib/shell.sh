# shell — wire the `wsctl` command into the user's shell, and take it back out again.
# This is the only module that edits a file outside the project, so it is sealed here and kept careful.
# Everything it writes lives in one marked block, rewritten whole each run so it never piles up — the same
# shape lib/visibility.sh uses for .git/info/exclude. The block defines a version-less, path-less locator:
# every project writes the identical function, and each call resolves to the project you are standing in and
# runs that project's own tool. install adds it; reset removes it. Never fatal — a shell we cannot write to
# just means the user runs `bash .wsctl/wsctl.sh` instead.

ALIAS_BEGIN="# wsctl-alias-begin"
ALIAS_END="# wsctl-alias-end"

# shell_rc_file — print the startup file for the user's shell, or fail if it is neither zsh nor bash.
shell_rc_file() {
  case "${SHELL:-}" in
    */zsh)  printf '%s/.zshrc'  "$HOME" ;;
    */bash) printf '%s/.bashrc' "$HOME" ;;
    *)      return 1 ;;
  esac
}

# shell_alias_block — the exact text written into the rc: the marker fence around the locator function.
# A quoted heredoc stores the body verbatim; it runs later, in the user's shell, not here.
shell_alias_block() {
  printf '%s\n' "$ALIAS_BEGIN"
  cat <<'WSCTL_ALIAS'
wsctl() {
  # Run the wsctl of whatever project you are in: walk up to the nearest .wsctl/wsctl.sh and run it there.
  local dir; dir="$(pwd -P)"
  while [ -n "$dir" ]; do
    if [ -d "$dir/.wsctl" ]; then
      if [ -f "$dir/.wsctl/wsctl.sh" ]; then
        ( cd "$dir" && bash .wsctl/wsctl.sh "$@" ); return $?
      fi
      printf '%s\n' "wsctl: wsctl isn't fully set up in this project. Initialize it in this project to use it." >&2
      return 1
    fi
    [ "$dir" = "/" ] && break
    dir="$(dirname "$dir")"
  done
  printf '%s\n' "wsctl: This project isn't set up with wsctl. Initialize it in this project, or switch to a project that already uses it." >&2
  return 1
}
WSCTL_ALIAS
  printf '%s\n' "$ALIAS_END"
}

# shell_strip_block <rc> — remove our marked block from <rc> in place (no-op if absent); non-zero on write failure.
shell_strip_block() {
  local rc="$1" tmp="$1.wsctl.tmp"
  sed "/$ALIAS_BEGIN/,/$ALIAS_END/d" "$rc" > "$tmp" 2>/dev/null && mv "$tmp" "$rc" && return 0
  rm -f "$tmp" 2>/dev/null; return 1
}

# shell_wire_alias — add or refresh the `wsctl` command in the user's rc. Each outcome gets its own message.
shell_wire_alias() {
  local rc had=0
  if ! rc="$(shell_rc_file)"; then
    warn "wsctl command not set up, because your shell is neither zsh nor bash — run it as: bash .wsctl/wsctl.sh <command>"
    return 0
  fi
  if [ ! -e "$rc" ] && ! : > "$rc" 2>/dev/null; then
    warn "wsctl command not set up, because $rc could not be created — run it as: bash .wsctl/wsctl.sh <command>"
    return 0
  fi
  if [ ! -w "$rc" ]; then
    warn "wsctl command not set up, because $rc is not writable — run it as: bash .wsctl/wsctl.sh <command>"
    return 0
  fi
  grep -qF "$ALIAS_BEGIN" "$rc" 2>/dev/null && had=1
  if ! shell_strip_block "$rc"; then
    warn "wsctl command not set up, because $rc could not be updated — run it as: bash .wsctl/wsctl.sh <command>"
    return 0
  fi
  shell_alias_block >> "$rc"
  if [ "$had" -eq 1 ]; then
    info "wsctl command already set up in $rc (refreshed)."
  else
    ok "wsctl command added to $rc — open a new terminal, or run: source $rc"
  fi
}

# shell_unwire_alias — remove the `wsctl` command from the user's rc (used by reset). No-op if we never wrote it.
shell_unwire_alias() {
  local rc
  rc="$(shell_rc_file)" || return 0
  [ -f "$rc" ] || return 0
  grep -qF "$ALIAS_BEGIN" "$rc" 2>/dev/null || return 0
  if [ ! -w "$rc" ]; then
    warn "wsctl command left in $rc — it is not writable to remove."
    return 0
  fi
  if shell_strip_block "$rc"; then ok "wsctl command removed from $rc."; else warn "wsctl command could not be removed from $rc."; fi
}
