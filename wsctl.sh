#!/usr/bin/env bash
# wsctl — entrypoint: finds its own directory, loads lib/*.sh, and runs the requested command.
# Run from your project root:  bash .wsctl/wsctl.sh <setup|update|status>   (--help for usage)
set -euo pipefail

# Apply --no-color before output.sh defines the colour variables.
for _a in "$@"; do [ "$_a" = "--no-color" ] && { COLOR=0; export COLOR; break; }; done

WSCTL_HOME="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; export WSCTL_HOME

# shellcheck source=/dev/null
for _m in output token config git visibility drift docker shell verbs; do . "$WSCTL_HOME/lib/$_m.sh"; done

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

main "$@"
