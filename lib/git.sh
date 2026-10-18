# git — git version check, scoped read-only token injection, and submodule clone/pull helpers.

# git_version — print the installed git version number.
git_version() { git --version 2>/dev/null | awk '{print $3}' || true; }
# version_ge <A> <B> — true when version A >= B. Portable (avoids `sort -V`, missing on old BSD).
version_ge() {
  awk -v a="$1" -v b="$2" 'BEGIN{
    na=split(a,x,"."); nb=split(b,y,"."); n=(na>nb)?na:nb
    for(i=1;i<=n;i++){ ai=(i<=na)?x[i]+0:0; bi=(i<=nb)?y[i]+0:0
      if(ai>bi){exit 0}; if(ai<bi){exit 1} } exit 0 }'
}
# require_git_version — stop with a clear message unless git is present and new enough.
require_git_version() {
  local v; v="$(git_version)"; [ -n "$v" ] || die "git not found on PATH"
  version_ge "$v" "$GIT_MIN" || die "git $v is too old — wsctl needs git >= $GIT_MIN (GIT_CONFIG_COUNT). Please update git."
}

# git_ro <token> <git args…> — run git with the token attached for github.com requests only.
# Security: the header is URL-scoped so no other host receives it; the token never enters the URL, argv, .git/config, or logs.
git_ro() {
  local tok="$1"; shift
  local b64; b64="$(printf 'x-access-token:%s' "$tok" | base64 | tr -d '\n')"
  GIT_TERMINAL_PROMPT=0 \
  GIT_CONFIG_COUNT=1 \
  GIT_CONFIG_KEY_0="http.${GH_MATCH}.extraHeader" \
  GIT_CONFIG_VALUE_0="Authorization: Basic ${b64}" \
    git "$@"
}

# current_branch <name> — print the submodule's branch, or (detached).
current_branch() { git -C "$ROOT/$1" symbolic-ref --quiet --short HEAD 2>/dev/null || printf '(detached)'; }
# ensure_on_branch <name> — check out DEFAULT_BRANCH if the submodule is on a detached HEAD.
ensure_on_branch() {
  git -C "$ROOT/$1" symbolic-ref -q HEAD >/dev/null 2>&1 && return 0
  git -C "$ROOT/$1" checkout -q "$DEFAULT_BRANCH" 2>/dev/null || true
}

# submodule_registered <name> — true when the parent repo already declares it (.gitmodules url or index gitlink).
submodule_registered() {
  local s="$1"
  git config -f "$ROOT/.gitmodules" --get "submodule.$s.url" >/dev/null 2>&1 && return 0
  git -C "$ROOT" ls-files --stage -- "$s" 2>/dev/null | grep -q '^160000 ' && return 0
  return 1
}
# set_ignore_local <name> — set submodule.<name>.ignore=all in .git/config so shell prompts stay quiet.
set_ignore_local() { git -C "$ROOT" config "submodule.$1.ignore" all >/dev/null 2>&1 || true; }
# unstage_pin <name> — drop any staged submodule pointer change; wsctl never moves the committed pointer.
unstage_pin() { git -C "$ROOT" restore --staged -- "$1" >/dev/null 2>&1 || true; }

# clean_broken_checkout <name> — remove a managed submodule's folder and stale .git/modules/<name> so it can be re-cloned.
# Leaves the committed pointer and .gitmodules alone; only acts on names in $SUBMODULES inside a git repo.
clean_broken_checkout() {
  local s="$1"
  [ -n "${ROOT:-}" ] && [ -n "$s" ] && valid_submodule "$s" || return 0
  git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || return 0   # refuse unless $ROOT is a real git repo
  git -C "$ROOT" submodule deinit -f "$s" >/dev/null 2>&1 || true
  rm -rf -- "$ROOT/.git/modules/$s" "$ROOT/$s" || true             # checkout + stale module only; bookmark untouched
}

# discard_dirty <name> — hard-discard local edits in a managed submodule (it is read-only, so they would only block pulls).
# Destructive by design; only acts on an existing, dirty checkout in $SUBMODULES.
discard_dirty() {
  local s="$1"; valid_submodule "$s" || return 0
  [ -e "$ROOT/$s/.git" ] || return 0
  [ -n "$(git -C "$ROOT/$s" status --porcelain 2>/dev/null)" ] || return 0
  debug "discarding local edits in $s (read-only, platform-owned)"   # housekeeping, shown only under -v
  git -C "$ROOT/$s" reset -q --hard
  git -C "$ROOT/$s" clean -qfd
}

# diagnose_pull <name> <git-output> — add one caution naming the reason a pull failed (auth, diverged, or dirty).
# The failing git command's own output is shown just above this, so these stay short.
diagnose_pull() {
  local s="$1" out="$2"
  case "$out" in
    *"could not read Username"*|*"Authentication failed"*|*"terminal prompts disabled"*|*"403"*)
      item warn "<path>$s</> auth failed — <path>$TOKEN_VAR</> is missing, expired, or under-scoped" ;;
    *"non-fast-forward"*|*"Not possible to fast-forward"*|*"diverged"*|*"have diverged"*)
      item warn "<path>$s</> diverged — local commits not on the remote" ;;
    *"local changes"*|*"overwritten"*|*"uncommitted"*|*"stash"*)
      item warn "<path>$s</> dirty — uncommitted local changes" ;;
    *) item warn "<path>$s</> pull failed — see the output above" ;;
  esac
}
