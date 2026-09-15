#!/bin/bash
# Undo niri-screen-up.sh: stop wayvnc and release the forced connector.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Host-specific values live in .env (see .env.example); it is gitignored.
[[ -f "$DIR/.env" ]] && . "$DIR/.env"
RUN="$DIR/run"
CONN="${CONN:-DP-1}"
CARD="${CARD:-card0}"
SYS="/sys/class/drm/${CARD}-${CONN}"


# $! after `setsid` is not reliably the pid of the exec'd program: setsid forks
# when the caller is already a process-group leader, and the grandchild's pid is
# never reported back. Resolving by a marker unique to this launch -- the socket
# path -- is exact, and unlike `pgrep -f` it cannot match the calling script,
# whose own command line does not contain that path.
pid_by_marker() {
    local marker="$1" p
    for p in /proc/[0-9]*; do
        [[ -r "$p/cmdline" ]] || continue
        if tr '\0' ' ' < "$p/cmdline" 2>/dev/null | grep -qF -- "$marker"; then
            basename "$p"
            return 0
        fi
    done
    return 1
}

pid="$(cat "$RUN/wayvnc-niri.pid" 2>/dev/null || true)"
# The pidfile is a hint, not the truth: fall back to the socket-path marker so a
# stale or wrong pidfile can never leave wayvnc orphaned holding the port.
if [[ -z "$pid" ]] || ! kill -0 "$pid" 2>/dev/null; then
    pid="$(pid_by_marker "$RUN/wayvnc-niri.sock" || true)"
fi
if true; then
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null
        for _ in $(seq 1 25); do kill -0 "$pid" 2>/dev/null || break; sleep 0.2; done
        kill -0 "$pid" 2>/dev/null && kill -KILL -- "-$pid" 2>/dev/null
        echo ":: stopped wayvnc (pid $pid)"
    else
        echo ":: wayvnc not running"
    fi
    rm -f "$RUN/wayvnc-niri.pid"
fi
rm -f "$RUN/wayvnc-niri.sock"

# The websocket wayvnc and the noVNC file server, same pidfile-is-a-hint rule.
for entry in "wayvnc-ws:$RUN/wayvnc-ws.sock" "novnc:$DIR/serve-novnc.py"; do
    name="${entry%%:*}"; marker="${entry#*:}"
    pid="$(cat "$RUN/$name.pid" 2>/dev/null || true)"
    if [[ -z "$pid" ]] || ! kill -0 "$pid" 2>/dev/null; then
        pid="$(pid_by_marker "$marker" || true)"
    fi
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null
        for _ in $(seq 1 25); do kill -0 "$pid" 2>/dev/null || break; sleep 0.2; done
        kill -0 "$pid" 2>/dev/null && kill -KILL -- "-$pid" 2>/dev/null
        echo ":: stopped $name (pid $pid)"
    fi
    rm -f "$RUN/$name.pid"
done
rm -f "$RUN/wayvnc-ws.sock"

# shellcheck disable=SC1090
. ~/.secrets >/dev/null 2>&1 || true
if [[ -n "${SUDO_PWD:-}" && -e "$SYS/status" ]]; then
    printf '%s\n' "$SUDO_PWD" | sudo -S -p '' sh -c "echo detect > '$SYS/status'"
    sleep 1
    echo ":: released $CONN (status now $(cat "$SYS/status"))"
fi
echo ":: niri second monitor down"
