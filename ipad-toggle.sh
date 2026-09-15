#!/bin/bash
# State machine behind the DankBar button. Kept as a script rather than inline
# QML so the behaviour can be tested from a shell.
#
#   ./ipad-toggle.sh status   -> prints one of: down | up | connected  (also the exit code: 0 | 1 | 2)
#   ./ipad-toggle.sh toggle   -> down -> up, anything else -> down
#   ./ipad-toggle.sh up | down
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Host-specific values live in .env (see .env.example); it is gitignored.
[[ -f "$DIR/.env" ]] && . "$DIR/.env"
RUN="$DIR/run"
PORT="${PORT:-5901}"
WS_PORT="${WS_PORT:-5902}"

status() {
    local pid
    pid="$(cat "$RUN/wayvnc-niri.pid" 2>/dev/null)"
    if [[ -z "$pid" ]] || ! kill -0 "$pid" 2>/dev/null; then
        echo down; return 0
    fi
    # A client is attached if anything is established against either the raw RFB
    # port or the WebSocket one -- Safari/noVNC lands on the latter.
    if ss -tnH state established "( sport = :$PORT or sport = :$WS_PORT )" 2>/dev/null | grep -q .; then
        echo connected; return 2
    fi
    echo up; return 1
}

case "${1:-status}" in
    status) status ;;
    up)     exec "$DIR/niri-screen-up.sh" ;;
    down)   exec "$DIR/niri-screen-down.sh" ;;
    toggle)
        if [[ "$(status)" == "down" ]]; then
            exec "$DIR/niri-screen-up.sh"
        else
            exec "$DIR/niri-screen-down.sh"
        fi
        ;;
    *) echo "usage: $0 {status|toggle|up|down}" >&2; exit 64 ;;
esac
