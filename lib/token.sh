# token — reads the read-only GitHub key from .env when needed; the user adds it by hand.
# Security: wsctl never prompts for, writes, or logs the key; a missing key simply stops the command.

# read_token — print the token, or nothing if absent. Always returns 0 (safe under set -e + pipefail).
read_token() {
  [ -f "$ROOT/.env" ] || return 0
  grep -E "^${TOKEN_VAR}=" "$ROOT/.env" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d '"'\'' ' || true
}

# env_is_set <name> — true when .env gives <name> a non-empty value ('name=' or a missing .env counts as unset).
# Security: wsctl never reads or logs .env contents — it only checks whether a key is set.
env_is_set() {
  [ -f "$ROOT/.env" ] || return 1
  grep -qE "^$1=.+" "$ROOT/.env" 2>/dev/null
}
