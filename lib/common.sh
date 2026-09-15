# Shared helpers. Sourced by the `second-screen` entrypoint, never run directly.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN="$ROOT/run"
mkdir -p "$RUN"

# Host-specific values. .env is gitignored; .env.example documents every key.
# shellcheck disable=SC1091
[[ -f "$ROOT/.env" ]] && . "$ROOT/.env"

CONN="${CONN:-DP-1}"          # must be DisplayPort; see display.sh
CARD="${CARD:-card0}"
DRI="${DRI:-0}"
W="${W:-2160}"                # the iPad 8 panel
H="${H:-1620}"
R="${R:-60}"
SCALE="${SCALE:-2}"
POS_X="${POS_X:-740}"         # logical position in the niri layout
POS_Y="${POS_Y:-1440}"
BIND="${BIND:-${HOST_IP:-}}"
PORT="${PORT:-5901}"
FPS="${FPS:-30}"
AUTOCONNECT="${AUTOCONNECT:-1}"
AUTOCONNECT_WAIT="${AUTOCONNECT_WAIT:-10}"

SYS="/sys/class/drm/${CARD}-${CONN}"
DBG="/sys/kernel/debug/dri/${DRI}/${CONN}"
VNC_SOCK="$RUN/wayvnc.sock"
VNC_PID="$RUN/wayvnc.pid"
VNC_LOG="$RUN/wayvnc.log"

say()  { printf ':: %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

require_config() {
    [[ -n "$BIND" ]] || die "HOST_IP is not set -- copy .env.example to .env"
}

# Wait up to $1 tenths of a second for a command to succeed.
wait_for() {
    local tries="$1"; shift
    for ((i = 0; i < tries; i++)); do
        "$@" && return 0
        sleep 0.1
    done
    return 1
}

port_listening() { ss -ltn 2>/dev/null | grep -q ":${1}\b"; }
port_has_client() { ss -tnH state established "( sport = :${1} )" 2>/dev/null | grep -q .; }

# `$!` after `setsid` is not reliably the pid of the exec'd program: setsid forks
# when the caller is already a process-group leader, and the grandchild's pid is
# never reported back. Resolving by a marker unique to the launch is exact, and
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

running() { [[ -f "$1" ]] && kill -0 "$(cat "$1")" 2>/dev/null; }

# Stop a process recorded in a pidfile. The pidfile is a hint, not the truth:
# fall back to the marker so a stale or wrong pidfile can never leave something
# orphaned holding a port.
stop_pidfile() {
    local label="$1" pidfile="$2" marker="$3" pid
    pid="$(cat "$pidfile" 2>/dev/null || true)"
    if [[ -z "$pid" ]] || ! kill -0 "$pid" 2>/dev/null; then
        pid="$(pid_by_marker "$marker" || true)"
    fi
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null
        local i
        for ((i = 0; i < 25; i++)); do
            kill -0 "$pid" 2>/dev/null || break
            sleep 0.2
        done
        kill -0 "$pid" 2>/dev/null && kill -KILL -- "-$pid" 2>/dev/null
        say "stopped $label (pid $pid)"
    else
        say "$label not running"
    fi
    rm -f "$pidfile"
}

# Root is needed only for the two sysfs/debugfs writes in display.sh.
# The password goes on stdin, never argv: /proc/<pid>/cmdline is world-readable.
as_root() {
    # shellcheck disable=SC1090
    [[ -n "${SUDO_PWD:-}" ]] || . ~/.secrets >/dev/null 2>&1 || true
    [[ -n "${SUDO_PWD:-}" ]] || die "SUDO_PWD not found in ~/.secrets"
    printf '%s\n' "$SUDO_PWD" | sudo -S -p '' "$@"
}
