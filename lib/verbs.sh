# verbs — install · update · status · health · reinstall · reset, plus arg dispatch.

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

OPTIONS
  -h, --help      Show this help
      --no-color  Plain output (auto when piped)
  install --force     Overwrite scaffolded config from templates
  install --check     Report present/missing config + submodules; non-zero if incomplete
EOF
}

install_check() {   # report present/missing config + submodules; non-zero if incomplete
  local incomplete=0 s name t
  info "config:"
  shopt -s nullglob dotglob
  for t in "$WSCTL_HOME"/templates/*; do
    name="$(basename -- "$t")"
    if [ -e "$ROOT/$name" ]; then ok "  $name"; else warn "  $name missing"; incomplete=1; fi
  done
  shopt -u nullglob dotglob
  info "submodules:"
  for s in $SUBMODULES; do
    if [ -e "$ROOT/$s/.git" ]; then ok "  $s on $(current_branch "$s")"; else warn "  $s not cloned"; incomplete=1; fi
  done
  return "$incomplete"
}

cmd_install() {
  local force="" check="" a
  for a in "$@"; do case "$a" in
    --force) force="--force" ;;
    --check) check=1 ;;
    --invisible) : ;;                                  # invisible is the only mode now (default) — flag kept as a harmless no-op
    -h|--help) info "usage: wsctl install [--force] [--check]"; return 0 ;;
    *) die "install: unknown arg '$a'" 2 ;;
  esac; done

  [ -n "$check" ] && { install_check; return $?; }

  # Visibility mode (WSCTL_MODE — the reserved seam). invisible is the ONLY supported mode; normal is PARKED.
  # Checked FIRST, before any work, so an unsupported mode fails fast with just that message — nothing laid,
  # no token read. That clean "not supported" message is the whole UX of choosing normal → known-issues.md.
  case "$WSCTL_MODE" in
    invisible) : ;;
    normal)    die "normal mode is not supported in this build — it is parked. Unset WSCTL_MODE (it defaults to invisible). → known-issues.md" ;;
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
  info "  next: set COMPOSE_PROJECT_NAME + DEVCONTAINER_INGRESS_PORT in .env, then Rebuild in Container."
}

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
    discard_dirty "$s"                                 # F7: platform-owned content; local edits are disposable
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

cmd_health() {   # read-only diagnosis: report invisible-mode drift; non-zero if any. No network, no token.
  local a; for a in "$@"; do case "$a" in
    -h|--help) info "usage: wsctl health"; return 0 ;;
    *) die "health: unknown arg '$a'" 2 ;;
  esac; done
  git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || die "$ROOT is not a git repository — run 'git init' (or clone) first"

  local drift; drift="$(drift_enumerate)"
  if [ -z "$drift" ]; then ok "healthy — both submodules present, on-branch, and hidden."; return 0; fi
  warn "drift detected:"
  printf '%s\n' "$drift" | while IFS=$'\t' read -r _ _ msg; do warn "  - $msg"; done
  info "  run 'wsctl reinstall' to rebuild a clean environment."
  return 1
}

cmd_reinstall() {   # reset + install: tear down the submodules' local git-state, then re-provision a clean set.
  # The explicit "give me a clean environment" verb — a thin composition of two built verbs, no repair logic of its own.
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

cmd_reset() {   # clean the submodules' local git-state so `install` can rebuild. Shared files untouched.
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
  echo >&2
  ok "reset done — run 'wsctl install' to rebuild."
  info "  shared files (.env / .mcp.json / .npmrc / docker-compose.client.yaml) were left untouched."
}

main() {
  local cmd="" args=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --no-color) : ;;                                 # handled before sourcing output.sh
      -h|--help)  if [ -z "$cmd" ]; then usage; exit 0; else args+=("$1"); fi ;;
      *)          if [ -z "$cmd" ]; then cmd="$1"; else args+=("$1"); fi ;;
    esac
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
    *)      die "unknown command '$cmd' (try: wsctl --help)" 2 ;;
  esac
}
