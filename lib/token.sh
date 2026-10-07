# token — read the read-only key from .env at point-of-use; never an ambient var, never logged.

read_token() {   # echoes the token or nothing. MUST return 0 even when absent (set -e + pipefail).
  [ -f "$ROOT/.env" ] || return 0
  grep -E "^${TOKEN_VAR}=" "$ROOT/.env" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d '"'\'' ' || true
}

persist_token() {   # persist_token <tok> → write into $ROOT/.env (0600). Keys are [A-Za-z0-9_], safe for the | delimiter.
  local tok="$1" tmp; tmp="$(mktemp)"
  if grep -qE "^${TOKEN_VAR}=" "$ROOT/.env" 2>/dev/null; then
    sed "s|^${TOKEN_VAR}=.*|${TOKEN_VAR}=${tok}|" "$ROOT/.env" > "$tmp"
  else
    { [ -f "$ROOT/.env" ] && cat "$ROOT/.env"; printf '%s=%s\n' "$TOKEN_VAR" "$tok"; } > "$tmp"
  fi
  mv "$tmp" "$ROOT/.env"; chmod 600 "$ROOT/.env"
}
