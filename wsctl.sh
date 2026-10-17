#!/usr/bin/env bash
# wsctl — entrypoint: finds its own directory, loads lib/*.sh, and runs the requested command.
# Run from your project root:  bash .wsctl/wsctl.sh <setup|update|status>   (--help for usage)
set -euo pipefail

# Apply --no-color before output.sh defines the colour variables.
for _a in "$@"; do [ "$_a" = "--no-color" ] && { COLOR=0; export COLOR; break; }; done

ROOT="$PWD"; export ROOT                                                 # the client project root
WSCTL_HOME="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; export WSCTL_HOME

# shellcheck source=/dev/null
for _m in output token config git visibility drift docker verbs; do . "$WSCTL_HOME/lib/$_m.sh"; done

main "$@"
