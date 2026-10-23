# verbs — the wsctl commands (install, update, status, health, reinstall, reset) and argument dispatch.

# usage — print the top-level help text.
usage() { cat <<'EOF'
wsctl — workspace control
Sync this project to target state: lay config from the platform skeleton, hold the read-only token,
and keep the managed submodules (.claude, devcontainers) current. Never rebuilds.

USAGE
  wsctl <command> [options]

COMMANDS
  install   Clone both submodules (hidden), lay config from the platform skeleton, capture the token. Idempotent.
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
  install --force     Overwrite scaffolded config with the platform default (your devcontainer edits are kept)
  install --check     Report present/missing config + submodules; non-zero if incomplete
EOF
}

# cmd_version — a small business card to stderr, and the bare version value to stdout. version is the one
# stdout=data case: a script reading `wsctl version` gets just `0.1.0`, so pipes stay clean, while the human
# reads the card. The tool version ships with the clone in the VERSION file; the workspace's config schema is a
# separate value in wsctl.toml, shown on the card when set but never mixed into the piped value. Pure local
# read — no key, no network.
cmd_version() {
  local a; for a in "$@"; do case "$a" in
    -h|--help) info "usage: wsctl version"; return 0 ;;
    *) die "version: unknown arg '$a'" 2 ;;
  esac; done
  local ver="" toml schema="" line
  [ -f "$WSCTL_HOME/VERSION" ] && ver="$(tr -d ' \t\n' < "$WSCTL_HOME/VERSION" 2>/dev/null || true)"
  [ -n "$ver" ] || ver="unknown"      # a clone always ships VERSION; stay quiet and honest if it's ever absent
  toml="$ROOT/$WSCTL_DIR/wsctl.toml"
  if [ -f "$toml" ]; then
    schema="$(awk -F= '/^[[:space:]]*schema[[:space:]]*=/{gsub(/[" \t\r]/,"",$2); print $2; exit}' "$toml" 2>/dev/null || true)"
  fi
  # The card → stderr (the human); colour follows the one palette.
  line="v$ver"; [ -n "$schema" ] && line="v$ver  ·  schema $schema"
  printf '  🪪  %s%swsctl%s %s· workspace control%s\n' "$C_BLD" "$C_LABEL" "$C_RST" "$C_DIM" "$C_RST" >&2
  printf '      %s%s%s\n' "$C_OK" "$line" "$C_RST" >&2
  printf '      %sgithub.com/Sevelantis/wsctl%s\n' "$C_DIM" "$C_RST" >&2
  # The bare value → stdout (a script).
  printf '%s\n' "$ver"
}

# install_check — report which submodules and provisioned files are present; non-zero if anything is missing.
# Config comes from the platform skeleton inside the devcontainers submodule, so it can only be verified once
# that submodule is cloned; before then, report the submodule as the thing to fix.
install_check() {
  local incomplete=0 s sk manifest blueprint dest policy
  info "submodules:"
  for s in $SUBMODULES; do
    if [ -e "$ROOT/$s/.git" ]; then ok "  $s on $(current_branch "$s")"; else warn "  $s not cloned"; incomplete=1; fi
  done
  info "config:"
  sk="$(skeleton_dir)"; manifest="$sk/provision.list"
  if [ ! -f "$manifest" ]; then
    warn "  not provisioned yet — run 'wsctl install' to clone the platform skeleton"; incomplete=1
  else
    while read -r blueprint dest policy; do
      case "$blueprint" in ''|'#'*) continue ;; esac
      [ -n "$dest" ] || continue
      if [ -e "$ROOT/$dest" ]; then ok "  $dest"; else warn "  $dest missing"; incomplete=1; fi
    done < "$manifest"
  fi
  return "$incomplete"
}

# .env keys needed to start the devcontainer, besides the read-only token (which has its own section).
REBUILD_ENV_VARS="COMPOSE_PROJECT_NAME DEVCONTAINER_INGRESS_PORT"

# report_env — one item per required .env key, set or not. The verb prints the section header around this.
# Security: wsctl never reads or logs .env contents — it only checks whether a key is set, never its value.
report_env() {
  local v unset=0
  for v in $REBUILD_ENV_VARS; do
    if env_is_set "$v"; then item ok "<path>$v</>"; else item warn "<path>$v</> not set"; unset=$((unset + 1)); fi
  done
  [ "$unset" -gt 0 ] && fix "set it in <path>.env</>, then rebuild"
  return 0
}

# _install_body — do the install and print its sections/items, deriving every line from live state. On the
# first blocking failure it sets the footer's words (_fail_kind + _fail_reason) and returns non-zero, leaving
# the caller to print the one closing footer (so `install` and `reinstall` can each stamp their own emoji).
_install_body() {
  local force="$1" tok
  # Checks first — nothing is written until the environment is known-good.
  if ! git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    section "🔎" "checks"; item fail "not a git repository here"; _fail_kind="stopped"; _fail_reason="not a git repo"; return 1
  fi
  require_git_version                                  # fatal pre-flight: git missing or too old

  section "🔑" "token"
  tok="$(read_token)"
  if [ -z "$tok" ]; then
    item fail "<path>$TOKEN_VAR</> not set in <path>.env</>"; _fail_kind="stopped"; _fail_reason="no GitHub PAT"; return 1
  fi
  item ok "<path>$TOKEN_VAR</> found in <path>.env</>"

  section "📥" "submodules"
  if ! provision_invisible "$tok"; then                # emits the pairs; on a failure, git's own output + a fix
    _fail_kind="incomplete"; _fail_reason="a clone failed"; return 1
  fi

  section "📦" "config"
  provision_managed seed "$force"                      # render the client skeleton from the pulled submodule

  section "🙈" "hidden"
  if vis_exclude_applied; then item ok "from <cmd>git status</>"; else item warn "not hidden from <cmd>git status</>"; fi

  section "🔗" "shell"
  shell_wire_alias                                     # emits the shell item (on PATH / a caution)

  section "🌱" "env"
  report_env                                           # emits one item per required .env key
  return 0
}

# cmd_install — clone and hide the managed submodules, lay config from the platform skeleton, wire the shell, check .env.
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

  _fail_kind=""; _fail_reason=""
  if _install_body "$force"; then
    summary "📦" ok "Installed." rebuild
  else
    summary "📦" fail "Install $_fail_kind — $_fail_reason."
    return 1
  fi
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

  local rc=0 s br out pre post n total=0 done_ok=0
  for s in $subs; do total=$((total + 1)); done
  section "🔄" "submodules"
  for s in $subs; do
    [ -e "$ROOT/$s/.git" ] || { pair fail "<path>$s</>" "not cloned"; fix "run <cmd>wsctl install</> first"; rc=1; continue; }
    discard_dirty "$s"                                 # platform-owned content; local edits are disposable
    br="$(current_branch "$s")"
    [ "$br" = "(detached)" ] && { pair warn "<path>$s</>" "detached — checkout a branch, then re-run"; rc=1; continue; }
    pre="$(git -C "$ROOT/$s" rev-parse HEAD 2>/dev/null || true)"
    debug "pull $br  ($s)"                              # the slow step, under -v; the pair below is the result
    if out="$(git_ro "$tok" -C "$ROOT/$s" pull --ff-only 2>&1)"; then
      post="$(git -C "$ROOT/$s" rev-parse HEAD 2>/dev/null || true)"
      n="$(git -C "$ROOT/$s" rev-list --count "$pre..$post" 2>/dev/null || printf '0')"
      if [ "${n:-0}" -gt 0 ]; then pair ok "<path>$s</>" "<branch>$br</> +$n"; else pair ok "<path>$s</>" "<branch>$br</> up to date"; fi
      done_ok=$((done_ok + 1))
    else
      case "$out" in *"non-fast-forward"*|*"rejected"*|*"fast-forward"*) pair fail "<path>$s</>" "pull rejected" ;; *) pair fail "<path>$s</>" "pull failed" ;; esac
      printf '%s\n' "$out" | while IFS= read -r _l; do cmdlog "$_l"; done   # git's own words, indented + dim
      diagnose_pull "$s" "$out"; rc=1
    fi
  done
  section "📦" "config"
  provision_managed sync                               # carry the client's provisioned pins forward after the pull
  if [ "$done_ok" -eq "$total" ]; then
    summary "♻️" ok "$done_ok/$total submodules updated."
  else
    summary "♻️" warn "$done_ok/$total submodules updated."
  fi
  return $rc
}

# cmd_status — read-only: each submodule's branch and dirty state (no network, no token). Always exits 0 — it
# reports, it never judges; `health` is the verb that fails on drift. The footer counts are derived live from
# what each submodule is actually in.
cmd_status() {
  # The raw pins are plumbing: shown only under -v.
  if [ "$VERBOSE" = 1 ]; then
    debug "submodule pins (git submodule status):"
    git -C "$ROOT" submodule status 2>/dev/null | while IFS= read -r _l; do debug "$_l"; done || true
  fi
  local s dirty br missing=0 edits=0
  section "📊" "submodules"
  for s in $SUBMODULES; do
    if [ ! -e "$ROOT/$s/.git" ]; then
      pair fail "<path>$s</>" "not cloned"; missing=$((missing + 1)); continue
    fi
    br="$(current_branch "$s")"
    dirty="$(git -C "$ROOT/$s" status --porcelain 2>/dev/null | grep -c . || true)"
    if [ "${dirty:-0}" -gt 0 ]; then
      pair warn "<path>$s</>" "<branch>$br</> · $dirty uncommitted"; edits=$((edits + 1))
    else
      pair ok "<path>$s</>" "<branch>$br</> · clean"
    fi
  done
  if [ "$missing" -gt 0 ]; then
    fix "run <cmd>wsctl install</>"
    summary "📊" warn "$missing submodule(s) missing."
  elif [ "$edits" -gt 0 ]; then
    summary "📊" warn "$edits submodule(s) with local edits."
  else
    summary "📊" ok "All submodules clean."
  fi
  return 0
}

# cmd_health — run the read-only drift checks, one item each, and close on a footer phrased from what was found.
# Exit is the contract tests pin: 0 when every check passed, non-zero when any failed (no network, no token).
cmd_health() {
  local a; for a in "$@"; do case "$a" in
    -h|--help) info "usage: wsctl health"; return 0 ;;
    *) die "health: unknown arg '$a'" 2 ;;
  esac; done
  git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || die "$ROOT is not a git repository — run 'git init' (or clone) first"

  section "🩺" "checks"
  if health_report; then
    summary "🩺" ok "Healthy. All checks passed."
    return 0
  fi
  if [ "$HEALTH_MISSING" -gt 0 ]; then
    summary "🩺" warn "$HEALTH_MISSING submodule(s) missing." rebuild
  else
    summary "🩺" warn "$HEALTH_ISSUES issue(s) found." rebuild
  fi
  return 1
}

# _reset_body — clean the submodules' local git-state and print its sections/items. Shared files are never
# touched. On the only blocking failure (not a git repo) it sets _fail_reason and returns non-zero; the caller
# prints the closing footer.
_reset_body() {
  local s
  if ! git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    item fail "not a git repository here"; _fail_reason="not a git repo"; return 1
  fi
  section "🧹" "cleaned"
  for s in $SUBMODULES; do
    clean_broken_checkout "$s"                         # deinit + rm .git/modules/<s> + rm the folder (idempotent)
    unstage_pin "$s"                                   # drop any staged gitlink; leave a committed bookmark alone
    item ok "<path>$s</>"
  done
  vis_remove_exclude                                   # strip the invisible hiding block so install re-applies fresh
  section "🙈" "visibility"; item ok "invisible mode deactivated"
  section "🔗" "shell";      shell_unwire_alias        # take the wsctl command back out of the user's shell rc
  return 0
}

# cmd_reset — the reset verb: the body, then one closing footer. Shared files are left untouched.
cmd_reset() {
  local a
  for a in "$@"; do case "$a" in
    -h|--help) info "usage: wsctl reset"; return 0 ;;
    *) die "reset: unknown arg '$a'" 2 ;;
  esac; done
  _fail_reason=""
  if _reset_body; then
    summary "🧹" ok "Cleaned." rebuild
  else
    summary "🧹" fail "Nothing to reset — $_fail_reason."
    return 1
  fi
}

# cmd_reinstall — reset then install, back to back, closing on one reinstall footer (not each phase's own).
cmd_reinstall() {
  local force="" a
  for a in "$@"; do case "$a" in
    --force) force="--force" ;;
    -h|--help) info "usage: wsctl reinstall [--force]"; return 0 ;;
    *) die "reinstall: unknown arg '$a'" 2 ;;
  esac; done
  _fail_kind=""; _fail_reason=""
  if ! _reset_body; then
    summary "🔁" fail "Reinstall stopped — $_fail_reason."
    return 1
  fi
  if _install_body "$force"; then
    summary "🔁" ok "Reinstalled." rebuild
  else
    summary "🔁" fail "Reinstall $_fail_kind — $_fail_reason."
    return 1
  fi
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
