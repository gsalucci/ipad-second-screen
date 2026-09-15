#!/bin/bash
# Stop the iPad second screen. Leaves the packages installed;
# use ./uninstall.sh to remove those too.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN="$DIR/run"


# $! after `setsid` is not reliably the pid of the exec'd program: setsid forks
# when the caller is already a process-group leader, and the grandchild's pid is
# never reported back. Resolving by a marker unique to this launch is exact, and
# unlike `pgrep -f` it cannot match the calling script, whose own command line
# does not contain that marker.
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

stop() {
    local name="$1" marker="$2" pidfile="$RUN/$1.pid" pid
    pid="$(cat "$pidfile" 2>/dev/null || true)"
    # The pidfile is a hint, not the truth: fall back to the unique marker so a
    # stale or wrong pidfile can never leave a process orphaned holding a port.
    if [[ -z "$pid" ]] || ! kill -0 "$pid" 2>/dev/null; then
        pid="$(pid_by_marker "$marker" || true)"
    fi
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        # Kill the process group: setsid made each one a group leader.
        kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null
        for _ in $(seq 1 25); do
            kill -0 "$pid" 2>/dev/null || break
            sleep 0.2
        done
        kill -0 "$pid" 2>/dev/null && kill -KILL -- "-$pid" 2>/dev/null
        echo ":: stopped $name (pid $pid)"
    else
        echo ":: $name not running"
    fi
    rm -f "$pidfile"
}

stop wayvnc "$RUN/wayvnc.sock"
stop sway   "$DIR/sway.conf"
rm -f "$RUN/sway-ipc.sock" "$RUN/wayvnc.sock" "$RUN/wayland_display"
echo ":: second screen down"
