# git — version floor, the URL-scoped read-only token injection, and submodule-state mechanics (F1–F7).

git_version() { git --version 2>/dev/null | awk '{print $3}' || true; }
version_ge() {   # version_ge A B → 0 if A >= B. Portable (no `sort -V`, absent on old BSD).
  awk -v a="$1" -v b="$2" 'BEGIN{
    na=split(a,x,"."); nb=split(b,y,"."); n=(na>nb)?na:nb
    for(i=1;i<=n;i++){ ai=(i<=na)?x[i]+0:0; bi=(i<=nb)?y[i]+0:0
      if(ai>bi){exit 0}; if(ai<bi){exit 1} } exit 0 }'
}
require_git_version() {
  local v; v="$(git_version)"; [ -n "$v" ] || die "git not found on PATH"
  version_ge "$v" "$GIT_MIN" || die "git $v is too old — wsctl needs git >= $GIT_MIN (GIT_CONFIG_COUNT). Please update git."
}

# git_ro <token> <git args…> — run git with the token injected ephemerally, SCOPED to github.com only.
# A URL-scoped extraHeader sends the Authorization ONLY to github.com; a bare one would leak it to any
# https host git contacts. The token never touches the URL, argv, .git/config, or logs.
git_ro() {
  local tok="$1"; shift
  local b64; b64="$(printf 'x-access-token:%s' "$tok" | base64 | tr -d '\n')"
  GIT_TERMINAL_PROMPT=0 \
  GIT_CONFIG_COUNT=1 \
  GIT_CONFIG_KEY_0="http.${GH_MATCH}.extraHeader" \
  GIT_CONFIG_VALUE_0="Authorization: Basic ${b64}" \
    git "$@"
}

current_branch() { git -C "$ROOT/$1" symbolic-ref --quiet --short HEAD 2>/dev/null || printf '(detached)'; }
ensure_on_branch() {   # land on DEFAULT_BRANCH if detached (belt-and-suspenders; `submodule add` usually lands on a branch)
  git -C "$ROOT/$1" symbolic-ref -q HEAD >/dev/null 2>&1 && return 0
  git -C "$ROOT/$1" checkout -q "$DEFAULT_BRANCH" 2>/dev/null || true
}

# submodule_registered <name> — the superproject already declares it (a .gitmodules url and/or an index gitlink).
submodule_registered() {
  local s="$1"
  git config -f "$ROOT/.gitmodules" --get "submodule.$s.url" >/dev/null 2>&1 && return 0
  git -C "$ROOT" ls-files --stage -- "$s" 2>/dev/null | grep -q '^160000 ' && return 0
  return 1
}
# set_ignore_local <name> — write ignore=all into .git/config every run (where the prompt reads it; F3).
set_ignore_local() { git -C "$ROOT" config "submodule.$1.ignore" all >/dev/null 2>&1 || true; }
# unstage_pin <name> — ensure no staged gitlink change; the bookmark is deliberate-only, wsctl never moves it (F2).
unstage_pin() { git -C "$ROOT" restore --staged -- "$1" >/dev/null 2>&1 || true; }

# clean_broken_checkout <name> — remove ONLY a broken/absent checkout (working dir + stale .git/modules/<name>)
# so a fresh `submodule update` can clone. NEVER touches the gitlink or .gitmodules — the pin stays frozen.
# Scoped to $SUBMODULES; reached only when $ROOT/<name>/.git is absent (never a healthy submodule).
clean_broken_checkout() {
  local s="$1"
  [ -n "${ROOT:-}" ] && [ -n "$s" ] && valid_submodule "$s" || return 0
  git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || return 0   # refuse unless $ROOT is a real git repo
  git -C "$ROOT" submodule deinit -f "$s" >/dev/null 2>&1 || true
  rm -rf -- "$ROOT/.git/modules/$s" "$ROOT/$s" || true             # checkout + stale module only; bookmark untouched
}

# discard_dirty <name> — F7: a managed submodule is READ-ONLY for the client, so local edits can never go
# upstream and only block the client's own fast-forward pull. Discard them (hard) so the pull can proceed.
# Scoped to $SUBMODULES; acts only on an existing, dirty checkout. Destructive by contract (platform-owned).
discard_dirty() {
  local s="$1"; valid_submodule "$s" || return 0
  [ -e "$ROOT/$s/.git" ] || return 0
  [ -n "$(git -C "$ROOT/$s" status --porcelain 2>/dev/null)" ] || return 0
  warn "  $s: discarding local changes (read-only, platform-owned)"
  git -C "$ROOT/$s" reset -q --hard
  git -C "$ROOT/$s" clean -qfd
}

# diagnose_pull <name> <git-output> — separate auth failure from dirty/diverged for a clear message.
diagnose_pull() {
  local s="$1" out="$2"
  case "$out" in
    *"could not read Username"*|*"Authentication failed"*|*"terminal prompts disabled"*|*"403"*)
      warn "$s: AUTH failed — $TOKEN_VAR is missing/expired/under-scoped (needs Contents:Read on $s), or (in-container) the gateway stripped the auth header." ;;
    *"non-fast-forward"*|*"Not possible to fast-forward"*|*"diverged"*|*"have diverged"*)
      warn "$s: DIVERGED — local commits not on the remote branch. Resolve with git, then re-run." ;;
    *"local changes"*|*"overwritten"*|*"uncommitted"*|*"stash"*)
      warn "$s: DIRTY — uncommitted local changes (wsctl should have discarded these; please report)." ;;
    *) warn "$s: pull failed — see git output above." ;;
  esac
}
