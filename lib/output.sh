# output — stderr logging helpers with colour when attached to a terminal (COLOR=1 force · 0 plain · auto).
COLOR="${COLOR:-auto}"
[ "$COLOR" = auto ] && { [ -t 2 ] && COLOR=1 || COLOR=0; }
if [ "$COLOR" = 0 ]; then C_RED=""; C_YEL=""; C_GRN=""; C_DIM=""; C_BLD=""; C_RST=""
else C_RED=$'\033[31m'; C_YEL=$'\033[33m'; C_GRN=$'\033[32m'; C_DIM=$'\033[2m'; C_BLD=$'\033[1m'; C_RST=$'\033[0m'; fi

# Verbose: reveal the plumbing (resolved paths, the git commands) through debug(). Off by default — verbosity is a
# request, never a default. Set by -v/--verbose or WSCTL_VERBOSE=1. It is NOT a raw `set -x` trace, and it never
# prints a secret: debug() is called only with paths and token-free commands.
VERBOSE="${VERBOSE:-0}"

log()   { printf '%s%s%s\n' "$C_DIM" "$*" "$C_RST" >&2; }
info()  { printf '%s\n' "$*" >&2; }
ok()    { printf '%s✓%s %s\n' "$C_GRN" "$C_RST" "$*" >&2; }
warn()  { printf '%s⚠%s %s\n' "$C_YEL" "$C_RST" "$*" >&2; }
die()   { printf '%s✗ %s%s\n' "$C_RED$C_BLD" "$*" "$C_RST" >&2; exit "${2:-1}"; }
debug() { [ "$VERBOSE" = 1 ] || return 0; printf '%s» %s%s\n' "$C_DIM" "$*" "$C_RST" >&2; }
