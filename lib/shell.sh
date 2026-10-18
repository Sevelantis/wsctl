# shell — wire the `wsctl` command into the user's shell, and take it back out again.
# This is the only module that edits a file outside the project, so it is sealed here and kept careful.
# Everything it writes lives in one marked block, rewritten whole each run so it never piles up — the same
# shape lib/visibility.sh uses for .git/info/exclude. The block defines a version-less, path-less locator:
# every project writes the identical function, and each call resolves to the project you are standing in and
# runs that project's own tool. install adds it; reset removes it. Never fatal — a shell we cannot write to
# just means the user runs `bash .wsctl/wsctl.sh` instead.

ALIAS_BEGIN="# wsctl-alias-begin"
ALIAS_END="# wsctl-alias-end"

# shell_rc_for <zsh|bash> — the startup file for that shell. zsh honours ZDOTDIR (common in managed setups);
# bash uses HOME.
shell_rc_for() {
  case "$1" in
    zsh)  printf '%s/.zshrc'  "${ZDOTDIR:-$HOME}" ;;
    bash) printf '%s/.bashrc' "$HOME" ;;
  esac
}

# shell_default_rc — the rc for the user's $SHELL, or fail if $SHELL is neither zsh nor bash.
shell_default_rc() {
  case "${SHELL:-}" in
    */zsh)  shell_rc_for zsh ;;
    */bash) shell_rc_for bash ;;
    *)      return 1 ;;
  esac
}

# shell_rc_targets — the rc files to wire the command into, one per line, de-duplicated: the $SHELL rc, PLUS any
# supported rc that already exists. The second part matters because the login shell ($SHELL) and the shell you
# actually type in can differ — writing only the $SHELL rc then leaves `wsctl` undefined in the shell you use.
# Fails (prints nothing) when $SHELL is unsupported and no supported rc exists.
shell_rc_targets() {
  local out="" def sh rc
  def="$(shell_default_rc 2>/dev/null || true)"
  [ -n "$def" ] && out="$def"
  for sh in zsh bash; do
    rc="$(shell_rc_for "$sh")"
    [ -f "$rc" ] || continue
    case " $out " in *" $rc "*) ;; *) out="${out:+$out }$rc" ;; esac
  done
  [ -n "$out" ] || return 1
  printf '%s\n' $out
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

# shell_wire_alias — add or refresh the `wsctl` command in every target rc (see shell_rc_targets). Writing to one
# rc never blocks the others, and a shell we cannot write to is never fatal — the user can still run the tool by
# path. Each outcome gets its own message.
shell_wire_alias() {
  local targets rc had any=0
  if ! targets="$(shell_rc_targets)"; then
    item warn "not set up, because your shell is neither zsh nor bash — run it as <cmd>bash .wsctl/wsctl.sh</>"
    return 0
  fi
  while IFS= read -r rc; do
    [ -n "$rc" ] || continue
    if [ ! -e "$rc" ] && ! : > "$rc" 2>/dev/null; then
      item warn "could not create <path>$rc</>"; continue
    fi
    if [ ! -w "$rc" ]; then
      item warn "<path>$rc</> is not writable"; continue
    fi
    had=0; grep -qF "$ALIAS_BEGIN" "$rc" 2>/dev/null && had=1
    if ! shell_strip_block "$rc"; then
      item warn "could not update <path>$rc</>"; continue
    fi
    # The rc may not end in a newline (e.g. a venv-activate snippet ending in `fi`); appending the
    # block directly would glue our marker onto that last line — breaking the shell and our own strip.
    [ -s "$rc" ] && [ -n "$(tail -c1 "$rc" 2>/dev/null)" ] && printf '\n' >> "$rc"
    shell_alias_block >> "$rc"; any=1
  done <<EOF
$targets
EOF
  if [ "$any" -eq 1 ]; then
    item ok "<cmd>wsctl</> on your PATH"
  else
    item warn "not set up anywhere — run it as <cmd>bash .wsctl/wsctl.sh</>"
  fi
  return 0
}

# shell_unwire_alias — remove the `wsctl` command from every supported rc that holds it (used by reset). It
# scans both shells, not just $SHELL, so the block is cleaned up wherever install may have written it. No-op if
# we never wrote it anywhere.
shell_unwire_alias() {
  local sh rc left=0
  for sh in zsh bash; do
    rc="$(shell_rc_for "$sh")"
    [ -f "$rc" ] || continue
    grep -qF "$ALIAS_BEGIN" "$rc" 2>/dev/null || continue
    if [ ! -w "$rc" ]; then item warn "left in <path>$rc</> — not writable to remove"; left=1; continue; fi
    shell_strip_block "$rc" || { item warn "could not remove from <path>$rc</>"; left=1; }
  done
  # Post-state is "not on PATH" whether we removed the block or it was never there; say so unless a write blocked it.
  [ "$left" -eq 0 ] && item ok "<cmd>wsctl</> removed from PATH"
  return 0
}
