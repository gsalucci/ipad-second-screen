#!/bin/bash
# Launch a command onto the iPad screen instead of the niri desktop.
#
#   ./screen-run.sh foot
#   ./screen-run.sh chromium --app=https://example.com
#
# Apps are started through sway's IPC so they inherit sway's environment,
# which is what puts them on the headless output rather than on DP-2.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN="$DIR/run"
SWAYSOCK_PATH="$RUN/sway-ipc.sock"

[[ -S "$SWAYSOCK_PATH" ]] || { echo "error: second screen is not up (run ./screen-up.sh)" >&2; exit 1; }
[[ $# -gt 0 ]] || { echo "usage: $0 <command> [args...]" >&2; exit 1; }

# Quote each argument so a command with spaces survives sway's exec parser.
cmd=""
for a in "$@"; do cmd+="$(printf '%q ' "$a")"; done

SWAYSOCK="$SWAYSOCK_PATH" swaymsg -q exec -- "$cmd"
echo ":: launched on the iPad screen: $*"
