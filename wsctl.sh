#!/usr/bin/env bash
# wsctl — workspace control. Entrypoint: resolve own dir, source lib/, dispatch.
# Run from your project root:  bash .wsctl/wsctl.sh <setup|update|status>   (--help for usage)
set -euo pipefail

# --no-color pre-scan: must set COLOR before any lib defines colour vars.
for _a in "$@"; do [ "$_a" = "--no-color" ] && { COLOR=0; export COLOR; break; }; done

ROOT="$PWD"; export ROOT                                                 # the client project root
WSCTL_HOME="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"; export WSCTL_HOME

# shellcheck source=/dev/null
for _m in output token config git visibility drift docker verbs; do . "$WSCTL_HOME/lib/$_m.sh"; done

main "$@"
