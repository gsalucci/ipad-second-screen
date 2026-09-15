#!/bin/bash
# Rung 2: give the LIVE niri session a real extra monitor, and stream it to the
# iPad. Unlike screen-up.sh this is a genuine extended desktop -- drag windows
# to it, move workspaces to it, same keybinds, same clipboard.
#
# Nothing persists. The whole thing is two writes into sysfs/debugfs plus a
# wayvnc process; a reboot undoes it with no trace, and ./niri-screen-down.sh
# undoes it immediately.
#
#   ./niri-screen-up.sh
#   CONN=DP-3 ./niri-screen-up.sh
#
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Host-specific values live in .env (see .env.example); it is gitignored.
[[ -f "$DIR/.env" ]] && . "$DIR/.env"
CONN="${CONN:-DP-1}"          # MUST be DisplayPort -- see the DVI note below
CARD="${CARD:-card0}"
DRI="${DRI:-0}"
W="${W:-2160}"
H="${H:-1620}"
R="${R:-60}"
SCALE="${SCALE:-2}"
# Centred below DP-2: the Dell is 2560x1440 logical at 0,0 and the iPad is
# 1080 logical wide at scale 2, so (2560-1080)/2 = 740.
POS_X="${POS_X:-740}"
POS_Y="${POS_Y:-1440}"
FPS="${FPS:-30}"
BIND="${BIND:-${HOST_IP:-}}"
PORT="${PORT:-5901}"          # 5900 belongs to rung 1; both can run at once
WS_PORT="${WS_PORT:-5902}"    # same output, WebSocket framing, for noVNC in Safari
WEB_PORT="${WEB_PORT:-6080}"  # static noVNC

RUN="$DIR/run"; mkdir -p "$RUN"
export XDG_CONFIG_HOME="$DIR/xdg"

die() { echo "error: $*" >&2; exit 1; }
alive() { [[ -f "$1" ]] && kill -0 "$(cat "$1")" 2>/dev/null; }

[[ -n "${BIND:-}" ]] || { echo "error: HOST_IP is not set -- copy .env.example to .env" >&2; exit 1; }
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


SYS="/sys/class/drm/${CARD}-${CONN}"
DBG="/sys/kernel/debug/dri/${DRI}/${CONN}"

[[ -e "$SYS/status" ]] || die "no such connector: $SYS"
[[ -n "${WAYLAND_DISPLAY:-}" ]] || die "WAYLAND_DISPLAY unset -- run this from inside the niri session"
command -v niri >/dev/null || die "niri not found"
alive "$RUN/wayvnc-niri.pid" && die "already running; ./niri-screen-down.sh first"

# A connector with no CEA-861 extension block is treated as DVI, and NVIDIA
# enforces the 165 MHz single-link DVI ceiling. 2160x1620@60 needs 232 MHz:
# accepted on DP-1, silently dropped on HDMI-A-1 (the mode list comes back with
# only the fallback 1024x768/800x600/640x480). Verified both ways on 580.178.04.
case "$CONN" in
    HDMI*) echo "warning: $CONN is HDMI. Without a CEA block the driver applies the" >&2
           echo "         165 MHz DVI limit, so ${W}x${H}@${R} will be rejected." >&2
           echo "         Use a DisplayPort connector, or drop R to ~40." >&2 ;;
esac

# shellcheck disable=SC1090
. ~/.secrets >/dev/null 2>&1 || true
[[ -n "${SUDO_PWD:-}" ]] || die "SUDO_PWD not in ~/.secrets"
# Password on stdin, never in argv: /proc/<pid>/cmdline is world-readable.
S() { printf '%s\n' "$SUDO_PWD" | sudo -S -p '' "$@"; }

EDID="$RUN/edid-${W}x${H}.bin"
EW="$W" EH="$H" ER="$R" python3 "$DIR/mkedid.py" "$EDID" >/dev/null
echo ":: generated EDID ${W}x${H}@${R} -> $EDID"

echo ":: forcing $CONN on with that EDID"
S sh -c "
    echo detect > '$SYS/status'
    cat '$EDID' > '$DBG/edid_override'
    echo on > '$SYS/status'
" || die "failed to force the connector (is debugfs mounted?)"

for _ in $(seq 1 25); do
    grep -qx "${W}x${H}" "$SYS/modes" 2>/dev/null && break
    sleep 0.2
done
grep -qx "${W}x${H}" "$SYS/modes" 2>/dev/null || {
    echo "modes offered: $(tr '\n' ' ' < "$SYS/modes")" >&2
    die "the driver rejected ${W}x${H}; see the DVI note above"
}
echo ":: $CONN is $(cat "$SYS/status"), offering ${W}x${H}"

echo ":: placing it in niri at ${POS_X},${POS_Y} scale ${SCALE}"
niri msg output "$CONN" on                        >/dev/null
niri msg output "$CONN" mode "${W}x${H}@${R}.000" >/dev/null || \
    niri msg output "$CONN" mode "${W}x${H}"      >/dev/null
niri msg output "$CONN" scale "$SCALE"            >/dev/null
niri msg output "$CONN" position set "$POS_X" "$POS_Y" >/dev/null

echo ":: starting wayvnc on ${BIND}:${PORT} capturing $CONN"
setsid wayvnc \
    --config "$DIR/wayvnc.conf" \
    --socket "$RUN/wayvnc-niri.sock" \
    --output "$CONN" \
    --max-fps "$FPS" \
    --render-cursor \
    --disable-resizing \
    "$BIND" "$PORT" >"$RUN/wayvnc-niri.log" 2>&1 &

for _ in $(seq 1 40); do
    ss -ltn 2>/dev/null | grep -q ":${PORT}\b" && break
    sleep 0.2
done
VNC_PID="$(pid_by_marker "$RUN/wayvnc-niri.sock" || true)"
[[ -n "$VNC_PID" ]] || { cat "$RUN/wayvnc-niri.log" >&2; die "wayvnc did not start"; }
echo "$VNC_PID" > "$RUN/wayvnc-niri.pid"
ss -ltn 2>/dev/null | grep -q ":${PORT}\b" || { cat "$RUN/wayvnc-niri.log" >&2; die "wayvnc never bound"; }

# Second wayvnc on the same output, in WebSocket mode, plus the static noVNC that
# talks to it. `--websocket` makes a listener WebSocket-only -- raw RFB clients
# get nothing on that port -- so this is a second instance rather than a flag on
# the first, and RealVNC keeps working on $PORT.
# Off by default: RealVNC on $PORT is the chosen client (full screen, no
# letterboxing), and the browser route is only worth its two extra processes when
# you actually want it. WEB=1 CLIENT=web turns it back on.
if [[ "${WEB:-0}" == "1" ]]; then
    echo ":: starting wayvnc (websocket) on ${BIND}:${WS_PORT}"
    setsid wayvnc \
        --config "$DIR/wayvnc.conf" \
        --socket "$RUN/wayvnc-ws.sock" \
        --output "$CONN" \
        --max-fps "$FPS" \
        --render-cursor \
        --disable-resizing \
        --websocket \
        "$BIND" "$WS_PORT" >"$RUN/wayvnc-ws.log" 2>&1 &
    for _ in $(seq 1 40); do
        ss -ltn 2>/dev/null | grep -q ":${WS_PORT}\b" && break
        sleep 0.2
    done
    WS_PID="$(pid_by_marker "$RUN/wayvnc-ws.sock" || true)"
    [[ -n "$WS_PID" ]] && echo "$WS_PID" > "$RUN/wayvnc-ws.pid"

    if ! ss -ltn 2>/dev/null | grep -q ":${WEB_PORT}\b"; then
        echo ":: serving noVNC on ${BIND}:${WEB_PORT}"
        BIND="$BIND" WEB_PORT="$WEB_PORT" setsid python3 "$DIR/serve-novnc.py" \
            >"$RUN/novnc.log" 2>&1 &
        for _ in $(seq 1 40); do
            ss -ltn 2>/dev/null | grep -q ":${WEB_PORT}\b" && break
            sleep 0.2
        done
        WEB_PID="$(pid_by_marker "$DIR/serve-novnc.py" || true)"
        [[ -n "$WEB_PID" ]] && echo "$WEB_PID" > "$RUN/novnc.pid"
    fi
fi

# Ask the iPad to open a client at us. Never fatal: the screen is useful with or
# without the tablet, and the tablet may simply be asleep.
if [[ "${AUTOCONNECT:-1}" == "1" ]]; then
    # If the iPad is sitting in the Home Screen web app, noVNC reconnects by
    # itself (reconnect=true, 2 s) as soon as wayvnc is listening again. Pushing
    # a URL in that case would yank the tablet into Safari and *lose* the full
    # screen, so wait for a self-reconnect first and only push if none arrives.
    for _ in $(seq 1 "${AUTOCONNECT_WAIT:-10}"); do
        if ss -tnH state established "( sport = :$PORT or sport = :$WS_PORT )" 2>/dev/null | grep -q .; then
            echo ":: the iPad reconnected on its own"
            break
        fi
        sleep 1
    done
    if ! ss -tnH state established "( sport = :$PORT or sport = :$WS_PORT )" 2>/dev/null | grep -q .; then
        HOST_IP="$BIND" PORT="$PORT" WS_PORT="$WS_PORT" WEB_PORT="$WEB_PORT" \
            "$DIR/ipad-connect.sh" || true
    fi
fi

cat <<EOF

  niri now has a second monitor
  ----------------------------------------------------------
  Safari (no tap, auto-connects)        http://${BIND}:${WEB_PORT}/vnc.html
  RealVNC (native, one OK tap)          ${BIND}:${PORT}
  output                                ${CONN}  ${W}x${H} @ scale ${SCALE}
  logical size                          $((W / SCALE))x$((H / SCALE)) at ${POS_X},${POS_Y}
  move a window there                   niri msg action move-window-to-monitor ${CONN}
  tear it down                          ./niri-screen-down.sh

  Nothing persists across a reboot. Re-run this script after one.
EOF
