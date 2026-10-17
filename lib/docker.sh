# docker — host Docker hygiene: routes `wsctl docker <sub>` to the scripts in lib/docker/, flags unchanged.
# `backup` is not wired in yet; audit and clean come first.

DOCKER_DIR="$WSCTL_HOME/lib/docker"

# docker_usage — print the `wsctl docker` help text to stderr.
docker_usage() {
  cat >&2 <<'EOF'
wsctl docker — host Docker hygiene (macOS / Docker Desktop; run on the host)
  wsctl docker audit [-v]                                      read-only disk report (changes nothing)
  wsctl docker clean [--soft|--images|--volumes|--dry-run]     reclaim regenerable space (soft = default)
  (backup)  not wired into wsctl yet — use the 'docker-backup' alias for now (coming soon)
Flags pass straight through, e.g.  wsctl docker clean --volumes --dry-run
EOF
}

# _docker_run <script> [args…] — run a script from lib/docker/, forwarding all args unchanged.
_docker_run() {
  local script="$1"; shift
  local path="$DOCKER_DIR/$script"
  [ -f "$path" ] || die "wsctl docker: missing '$script' under $DOCKER_DIR — reinstall wsctl" 69
  bash "$path" "$@"                                  # child process: the script's own `set`/BASH_SOURCE apply
}

# cmd_docker — dispatch `wsctl docker <audit|clean>`.
cmd_docker() {
  local sub="${1:-}"; [ $# -gt 0 ] && shift
  case "$sub" in
    ""|-h|--help) docker_usage; return 0 ;;
    audit) _docker_run "docker-space-audit.sh" "$@" ;;
    clean) _docker_run "docker-cleanup.sh" "$@" ;;
    backup) die "wsctl docker backup is not wired into wsctl yet — use the 'docker-backup' alias for now (coming soon)" 2 ;;
    *) die "unknown 'wsctl docker' subcommand '$sub' (try: wsctl docker --help)" 2 ;;
  esac
}
