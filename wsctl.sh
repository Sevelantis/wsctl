#!/usr/bin/env bash
# wsctl — entrypoint: finds its own directory, loads lib/*.sh, and runs the requested command.
# Run from your project root:  bash .wsctl/wsctl.sh <setup|update|status>   (--help for usage)
set -euo pipefail

# Pre-scan global flags before output.sh reads them: --no-color (colour) and -v/--verbose (plumbing detail).
# Globals belong BEFORE the command; anything after the command is the command's own (e.g. `docker audit -v`
# forwards -v to the wrapped script), so -v only counts as global until the first bareword. WSCTL_VERBOSE=1 does
# the same as a leading -v, convenient for wrapping a run in a script without changing the invocation.
VERBOSE="${WSCTL_VERBOSE:-0}"; [ "$VERBOSE" = 1 ] || VERBOSE=0
_seen_cmd=0
for _a in "$@"; do case "$_a" in
  --no-color)   COLOR=0; export COLOR ;;                 # wsctl's own; harmless anywhere
  -v|--verbose) [ "$_seen_cmd" = 0 ] && VERBOSE=1 ;;      # global only before the command
  -*)           : ;;                                      # some other flag; keep scanning
  *)            _seen_cmd=1 ;;                            # the command (and its args) begin here
esac; done
unset _seen_cmd
export VERBOSE

WSCTL_HOME="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; export WSCTL_HOME

# shellcheck source=/dev/null
for _m in output ui token config git visibility drift docker shell verbs; do . "$WSCTL_HOME/lib/$_m.sh"; done

# Resolve the project root from where the tool is installed, not from $PWD — so every verb behaves the
# same whether you run it from the project root or from inside the launcher dir. A client always has the
# tool at <project>/<WSCTL_DIR>/wsctl.sh, so the project root is that dir's parent. Any other layout (a
# dev checkout or submodule named differently, the tests) has no such anchor and keeps the $PWD contract.
if [ "$(basename -- "$WSCTL_HOME")" = "$WSCTL_DIR" ]; then
  ROOT="$(dirname -- "$WSCTL_HOME")"
else
  ROOT="$PWD"
fi
export ROOT

debug "home=$WSCTL_HOME  root=$ROOT  mode=$WSCTL_MODE"

main "$@"
