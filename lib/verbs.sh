# verbs — the wsctl commands (install, update, status, health, reinstall, reset) and argument dispatch.

# usage — print the top-level help text.
usage() { cat <<'EOF'
wsctl — workspace control
Sync this project to target state: lay config from templates, hold the read-only token,
and keep the managed submodules (.claude, devcontainers) current. Never rebuilds.

USAGE
  wsctl <command> [options]

COMMANDS
  install   Lay config from templates, capture the token, clone both submodules (hidden). Idempotent.
  update    Pull both submodules' current branch (git pull --ff-only). [submodule] optional.
  status    Read-only: each submodule's branch + dirty state. No network, no token.
  health    Read-only: report drift (missing / detached / un-hidden submodules). No network, no token.
  reinstall Reset then install — rebuild a clean submodule set. Needs the token. Never touches shared files.
  reset     Clean the submodules' local git-state so 'install' can rebuild. Never touches shared files.
  docker    Host Docker hygiene: 'wsctl docker audit|clean' (wraps docker-health). Run on the host.
  version   Print the tool version (and the workspace's config schema, if set).

OPTIONS
  -h, --help      Show this help
  -V, --version   Print the tool version and exit
  -v, --verbose   Show the plumbing (resolved paths, git commands); never prints a secret
      --no-color  Plain output (auto when piped)
  install --force     Overwrite scaffolded config from templates
  install --check     Report present/missing config + submodules; non-zero if incomplete
EOF
}

# cmd_version — print the tool version (data → stdout), plus the workspace config schema when wsctl.toml sets it.
# The tool version ships with the clone in the VERSION file; the schema is a separate, workspace-owned value.
cmd_version() {
  local a; for a in "$@"; do case "$a" in
    -h|--help) info "usage: wsctl version"; return 0 ;;
    *) die "version: unknown arg '$a'" 2 ;;
  esac; done
  local ver="" line toml schema
  [ -f "$WSCTL_HOME/VERSION" ] && ver="$(tr -d ' \t\n' < "$WSCTL_HOME/VERSION" 2>/dev/null || true)"
  [ -n "$ver" ] || ver="unknown"      # a clone always ships VERSION; stay quiet and honest if it's ever absent
  line="wsctl $ver"
  toml="$ROOT/$WSCTL_DIR/wsctl.toml"
  if [ -f "$toml" ]; then
    schema="$(awk -F= '/^[[:space:]]*schema[[:space:]]*=/{gsub(/[" \t\r]/,"",$2); print $2; exit}' "$toml" 2>/dev/null || true)"
    [ -n "$schema" ] && line="$line · workspace schema $schema"
  fi
  printf '%s\n' "$line"
}

# install_check — report which config files and submodules are present; non-zero if any is missing.
install_check() {
  local incomplete=0 s rel t
  info "config:"
  while IFS= read -r t; do
    rel="${t#"$WSCTL_HOME"/templates/}"           # relative path = its destination under $ROOT (mirrors provision_config)
    if [ -e "$ROOT/$rel" ]; then ok "  $rel"; else warn "  $rel missing"; incomplete=1; fi
  done < <(find "$WSCTL_HOME/templates" -type f)
  info "submodules:"
  for s in $SUBMODULES; do
    if [ -e "$ROOT/$s/.git" ]; then ok "  $s on $(current_branch "$s")"; else warn "  $s not cloned"; incomplete=1; fi
  done
  return "$incomplete"
}

# .env keys needed to start the devcontainer, besides the read-only token.
REBUILD_ENV_VARS="COMPOSE_PROJECT_NAME DEVCONTAINER_INGRESS_PORT"

# report_env — show which required .env keys are set, at the end of install.
# Security: wsctl never reads or logs .env contents — it only checks whether a key is set.
report_env() {
  local v all=1
  info "  .env (values never shown):"
  if env_is_set "$TOKEN_VAR"; then ok "  $TOKEN_VAR set"; else warn "  $TOKEN_VAR not set"; all=0; fi
  for v in $REBUILD_ENV_VARS; do
    if env_is_set "$v"; then ok "  $v set"; else warn "  $v not set"; all=0; fi
  done
  if [ "$all" -eq 1 ]; then
    ok "  .env ready — Rebuild in Container to start."
  else
    info "  set the key(s) marked 'not set' in .env by hand, then Rebuild in Container."
  fi
}

# cmd_install — lay config from templates, then clone and hide the managed submodules.
cmd_install() {
  local force="" check="" a
  for a in "$@"; do case "$a" in
    --force) force="--force" ;;
    --check) check=1 ;;
    --invisible) : ;;                                  # invisible is the default mode; flag kept as a no-op for compatibility
    -h|--help) info "usage: wsctl install [--force] [--check]"; return 0 ;;
    *) die "install: unknown arg '$a'" 2 ;;
  esac; done

  [ -n "$check" ] && { install_check; return $?; }

  # Only invisible mode is supported. Checked first so an unsupported mode fails before anything is changed.
  case "$WSCTL_MODE" in
    invisible) : ;;
    normal)    die "normal mode is not supported in this build — it is not available yet. Unset WSCTL_MODE (it defaults to invisible)." ;;
    *)         die "unknown WSCTL_MODE '$WSCTL_MODE' (supported: invisible)" 2 ;;
  esac

  provision_config "$force"

  git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || die "$ROOT is not a git repository — run 'git init' (or clone) first"
  require_git_version

  local tok; tok="$(read_token)"
  [ -n "$tok" ] || die "$TOKEN_VAR is not set in $ROOT/.env — add your read-only token by hand, then re-run."

  provision_invisible "$tok" || die "install incomplete — a submodule could not be set up (see ⚠ above)"

  echo >&2
  ok "onboarding ready — submodules in place (invisible)."
  shell_wire_alias
  report_env
}

# cmd_update — fast-forward each managed submodule (or just the one named) from its remote.
cmd_update() {
  local only="" a
  for a in "$@"; do case "$a" in
    -h|--help) info "usage: wsctl update [submodule]"; return 0 ;;
    -*) die "update takes no flags ('--force' belongs to install) — got '$a'" 2 ;;
    *) only="$a" ;;
  esac; done

  require_git_version
  local tok; tok="$(read_token)"
  [ -n "$tok" ] || die "$TOKEN_VAR is not set in $ROOT/.env — add your read-only token, or run 'wsctl install'."

  local subs="$SUBMODULES"
  if [ -n "$only" ]; then
    valid_submodule "$only" || die "unknown submodule '$only' (expected: $SUBMODULES)" 2
    subs="$only"
  fi

  local rc=0 s br out
  for s in $subs; do
    [ -e "$ROOT/$s/.git" ] || { warn "$s: not cloned — run 'wsctl install'"; rc=1; continue; }
    discard_dirty "$s"                                 # platform-owned content; local edits are disposable
    br="$(current_branch "$s")"
    [ "$br" = "(detached)" ] && { warn "$s: detached HEAD — checkout a branch first, then re-run"; rc=1; continue; }
    info "→ $s: pull $br"
    if out="$(git_ro "$tok" -C "$ROOT/$s" pull --ff-only 2>&1)"; then
      printf '%s\n' "$out" | sed 's/^/    /' >&2   # git's own output: diffstat on a real pull, else "Already up to date."
      ok "$s: on $br"
    else
      printf '%s\n' "$out" | sed 's/^/    /' >&2
      diagnose_pull "$s" "$out"; rc=1
    fi
  done
  return $rc
}

# cmd_status — show each submodule's branch and uncommitted-file count (no network, no token).
cmd_status() {
  info "submodule pins (git submodule status):"
  git -C "$ROOT" submodule status 2>/dev/null | sed 's/^/  /' >&2 || true
  local s dirty
  for s in $SUBMODULES; do
    if [ -e "$ROOT/$s/.git" ]; then
      dirty="$(git -C "$ROOT/$s" status --porcelain 2>/dev/null | grep -c . || true)"
      info "  $s: on $(current_branch "$s") · ${dirty:-0} uncommitted file(s)"
    else
      warn "  $s: not cloned"
    fi
  done
}

# cmd_health — run the read-only checks, showing each as ✓/⚠; non-zero if any failed (no network, no token).
cmd_health() {
  local a; for a in "$@"; do case "$a" in
    -h|--help) info "usage: wsctl health"; return 0 ;;
    *) die "health: unknown arg '$a'" 2 ;;
  esac; done
  git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || die "$ROOT is not a git repository — run 'git init' (or clone) first"

  info "health — read-only checks (no network, no key):"
  if health_report; then ok "healthy — all checks passed."; return 0; fi
  info "  run 'wsctl reinstall' to rebuild a clean environment."
  return 1
}

# cmd_reinstall — run reset, then install, to rebuild a clean submodule set.
cmd_reinstall() {
  local force="" a
  for a in "$@"; do case "$a" in
    --force) force="--force" ;;
    -h|--help) info "usage: wsctl reinstall [--force]"; return 0 ;;
    *) die "reinstall: unknown arg '$a'" 2 ;;
  esac; done
  info "→ reinstall: reset, then install …"
  cmd_reset
  echo >&2
  cmd_install ${force:+"$force"}
}

# cmd_reset — remove the managed submodules' local checkouts so `install` can rebuild them; shared files untouched.
cmd_reset() {
  local a s
  for a in "$@"; do case "$a" in
    -h|--help) info "usage: wsctl reset"; return 0 ;;
    *) die "reset: unknown arg '$a'" 2 ;;
  esac; done

  git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || die "$ROOT is not a git repository — nothing to reset"
  info "→ reset: cleaning the submodules' local git-state (shared files untouched) …"
  for s in $SUBMODULES; do
    clean_broken_checkout "$s"                         # deinit + rm .git/modules/<s> + rm the folder (idempotent)
    unstage_pin "$s"                                   # drop any staged gitlink; leave a committed bookmark alone
    ok "  $s: cleaned"
  done
  vis_remove_exclude                                   # strip the invisible hiding block so install re-applies fresh
  shell_unwire_alias                                   # take the wsctl command back out of the user's shell rc
  echo >&2
  ok "reset done — run 'wsctl install' to rebuild."
  info "  shared files (.env / .mcp.json / .npmrc / docker-compose.client.yaml) were left untouched."
}

# main — parse global flags, pick the command, and run it.
main() {
  local cmd="" args=()
  while [ $# -gt 0 ]; do
    if [ -z "$cmd" ]; then
      case "$1" in                                     # before the command: wsctl's own global flags
        --no-color)   : ;;                             # handled before sourcing output.sh
        -v|--verbose) : ;;                             # consumed in the pre-scan
        -V|--version) cmd="version" ;;
        -h|--help)    usage; exit 0 ;;
        *)            cmd="$1" ;;
      esac
    else
      case "$1" in                                     # after the command: the command's own args, verbatim
        --no-color) : ;;                               # the one exception — wsctl's colour flag, never forwarded
        *)          args+=("$1") ;;
      esac
    fi
    shift
  done
  [ -n "$cmd" ] || { usage >&2; exit 2; }              # usage-on-error → stderr; explicit --help → stdout
  case "$cmd" in
    install) cmd_install ${args[@]+"${args[@]}"} ;;
    update)  cmd_update  ${args[@]+"${args[@]}"} ;;
    status)  cmd_status  ${args[@]+"${args[@]}"} ;;
    health)    cmd_health    ${args[@]+"${args[@]}"} ;;
    reinstall) cmd_reinstall ${args[@]+"${args[@]}"} ;;
    reset)     cmd_reset     ${args[@]+"${args[@]}"} ;;
    docker)    cmd_docker    ${args[@]+"${args[@]}"} ;;
    version)   cmd_version   ${args[@]+"${args[@]}"} ;;
    *)      die "unknown command '$cmd' (try: wsctl --help)" 2 ;;
  esac
}
