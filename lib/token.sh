# token — read the read-only key from .env at point-of-use; never an ambient var, never logged.
# The key is added BY HAND to .env by the user (UC-1); wsctl never prompts for or writes it — a missing
# key is a plain hard-stop. (The interactive prompt + persist_token were cut 2026-10-15: CUT 1.)

read_token() {   # echoes the token or nothing. MUST return 0 even when absent (set -e + pipefail).
  [ -f "$ROOT/.env" ] || return 0
  grep -E "^${TOKEN_VAR}=" "$ROOT/.env" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d '"'\'' ' || true
}
