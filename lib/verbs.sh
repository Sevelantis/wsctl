# verbs — setup · update · status, plus arg dispatch. (doctor/health/reset: reserved slots, next gate.)

usage() { cat <<'EOF'
wsctl — workspace control
Sync this project to target state: lay config from templates, hold the read-only token,
and keep the managed submodules (.claude, devcontainers) current. Never rebuilds.

USAGE
  wsctl <command> [options]

COMMANDS
  setup     Lay config from templates, capture the token, clone/register both submodules. Idempotent.
  update    Pull both submodules' current branch (git pull --ff-only). [submodule] optional.
  status    Read-only: each submodule's branch + dirty state. No network, no token.

OPTIONS
  -h, --help      Show this help
      --no-color  Plain output (auto when piped)
  setup --force   Overwrite scaffolded config from templates
  setup --check   Report present/missing config + submodules; non-zero if incomplete
EOF
}

setup_check() {   # report present/missing config + submodules; non-zero if incomplete
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

cmd_setup() {
  local force="" check="" invisible="" a
  for a in "$@"; do case "$a" in
    --force) force="--force" ;;
    --check) check=1 ;;
    --invisible) invisible=1 ;;
    -h|--help) info "usage: wsctl setup [--force] [--check] [--invisible]"; return 0 ;;
    *) die "setup: unknown arg '$a'" 2 ;;
  esac; done

  [ -n "$check" ] && { setup_check; return $?; }

  provision_config "$force"

  git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || die "$ROOT is not a git repository — run 'git init' (or clone) first"
  require_git_version

  local tok; tok="$(read_token)"
  if [ -z "$tok" ]; then
    printf 'Paste your READ-ONLY GitHub token (%s) — input hidden: ' "$TOKEN_VAR" >&2
    read -rs tok; echo >&2
    [ -n "$tok" ] || die "no token entered"
    persist_token "$tok"; ok "token saved to .env (0600)"
  else
    log "$TOKEN_VAR already set in .env"
  fi

  # Invisible mode (opt-in for now): plain clones hidden via .git/info/exclude — no pin, no .gitmodules.
  if [ -n "$invisible" ]; then
    provision_invisible "$tok" || die "setup incomplete — a submodule could not be set up (see ⚠ above)"
    echo >&2
    ok "onboarding ready — submodules in place (invisible)."
    info "  next: set COMPOSE_PROJECT_NAME + DEVCONTAINER_INGRESS_PORT in .env, then Rebuild in Container."
    return 0
  fi

  local rc=0 s out
  info "→ ensuring submodules …"
  for s in $SUBMODULES; do
    set_ignore_local "$s"                              # every run — where the prompt reads it (F3)
    if [ -e "$ROOT/$s/.git" ]; then
      discard_dirty "$s"; ensure_on_branch "$s"; unstage_pin "$s"
      log "  $s: present — on $(current_branch "$s") (use 'wsctl update' to pull)"
      continue
    fi
    if submodule_registered "$s"; then
      # Pre-declared by the repo template (or a half-registered prior run): the bookmark already exists.
      # NEVER re-`add` it — that moves+stages the pin and blocks the client's own `git pull` (F2).
      clean_broken_checkout "$s"
      if out="$(git_ro "$tok" -C "$ROOT" submodule update --init --remote -- "$s" 2>&1)"; then
        set_ignore_local "$s"; ensure_on_branch "$s"; unstage_pin "$s"
        ok "  $s: initialized (on $(current_branch "$s"))"
      else
        printf '%s\n' "$out" | sed 's/^/      /' >&2
        warn "  $s: init FAILED — check $TOKEN_VAR has Contents:Read on $(url_for "$s")"; rc=1
      fi
    else
      # Truly absent — never declared. The ONE intended time we set the pin (the bookmark's birth).
      if out="$(git_ro "$tok" -C "$ROOT" submodule add "$(url_for "$s")" "$s" 2>&1)"; then
        git config -f "$ROOT/.gitmodules" "submodule.$s.ignore" all >/dev/null 2>&1 || true
        set_ignore_local "$s"; ensure_on_branch "$s"
        ok "  $s: added (on $(current_branch "$s"))"
      else
        printf '%s\n' "$out" | sed 's/^/      /' >&2
        warn "  $s: add FAILED — check $TOKEN_VAR has Contents:Read on $(url_for "$s")"; rc=1
      fi
    fi
  done

  echo >&2
  [ "$rc" = 0 ] || die "setup incomplete — a submodule could not be set up (see ⚠ above)"
  ok "onboarding ready — submodules in place."
  info "  next: set COMPOSE_PROJECT_NAME + DEVCONTAINER_INGRESS_PORT in .env, then Rebuild in Container."
}

cmd_update() {
  local only="" a
  for a in "$@"; do case "$a" in
    -h|--help) info "usage: wsctl update [submodule]"; return 0 ;;
    -*) die "update takes no flags ('--force' belongs to setup) — got '$a'" 2 ;;
    *) only="$a" ;;
  esac; done

  require_git_version
  local tok; tok="$(read_token)"
  [ -n "$tok" ] || die "$TOKEN_VAR is not set in $ROOT/.env — add your read-only token, or run 'wsctl setup'."

  local subs="$SUBMODULES"
  if [ -n "$only" ]; then
    valid_submodule "$only" || die "unknown submodule '$only' (expected: $SUBMODULES)" 2
    subs="$only"
  fi

  local rc=0 s br out
  for s in $subs; do
    [ -e "$ROOT/$s/.git" ] || { warn "$s: not cloned — run 'wsctl setup'"; rc=1; continue; }
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
    setup)  cmd_setup  ${args[@]+"${args[@]}"} ;;
    update) cmd_update ${args[@]+"${args[@]}"} ;;
    status) cmd_status ${args[@]+"${args[@]}"} ;;
    *)      die "unknown command '$cmd' (try: wsctl --help)" 2 ;;
  esac
}
