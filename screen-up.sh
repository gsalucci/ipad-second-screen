#!/bin/bash
# Bring up the iPad second screen: headless sway + wayvnc on the LAN.
#
# Nothing here touches the running niri session. Sway runs on the headless
# wlroots backend -- no DRM, no seat, no TTY -- as an ordinary uid 1000
# process. Config and runtime state stay inside this directory.
#
#   ./screen-up.sh            # 2160x1620 @ scale 2, matches the iPad panel
#   W=1620 H=1215 SCALE=1.5 ./screen-up.sh
#
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Host-specific values live in .env (see .env.example); it is gitignored.
[[ -f "$DIR/.env" ]] && . "$DIR/.env"
W="${W:-2160}"
H="${H:-1620}"
SCALE="${SCALE:-2}"
FPS="${FPS:-30}"
BIND="${BIND:-${HOST_IP:-}}"
PORT="${PORT:-5900}"

export XDG_CONFIG_HOME="$DIR/xdg"
RUN="$DIR/run"
mkdir -p "$RUN"

SWAYSOCK_PATH="$RUN/sway-ipc.sock"
VNCSOCK_PATH="$RUN/wayvnc.sock"

die() { echo "error: $*" >&2; exit 1; }

# pgrep -f would match this script's own command line; compare PIDs instead.
alive() { [[ -f "$1" ]] && kill -0 "$(cat "$1")" 2>/dev/null; }
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


if alive "$RUN/sway.pid"; then
    die "already running (sway pid $(cat "$RUN/sway.pid")). Run ./screen-down.sh first."
fi

[[ -n "${XDG_RUNTIME_DIR:-}" ]] || die "XDG_RUNTIME_DIR unset"

# --- sway -------------------------------------------------------------------
echo ":: starting headless sway (${W}x${H} @ scale ${SCALE})"
# WLR_RENDERER=pixman is required, not a preference. With the default gles2
# renderer on the headless backend, wayvnc's capture returns a uniform #606060
# frame: verified by connecting a raw RFB client with a window on screen and
# counting exactly one distinct colour across 2160x1620. The same test under
# pixman returns the real desktop. Software rendering is also why max-fps
# defaults to 30 rather than 60.
WLR_BACKENDS=headless \
WLR_HEADLESS_OUTPUTS=1 \
WLR_LIBINPUT_NO_DEVICES=1 \
WLR_RENDERER="${WLR_RENDERER:-pixman}" \
SWAYSOCK="$SWAYSOCK_PATH" \
    setsid sway -c "$DIR/sway.conf" >"$RUN/sway.log" 2>&1 &

for _ in $(seq 1 50); do
    [[ -S "$SWAYSOCK_PATH" ]] && break
    sleep 0.2
done
SWAY_PID="$(pid_by_marker "$DIR/sway.conf" || true)"
[[ -n "$SWAY_PID" ]] || die "sway did not start; see $RUN/sway.log"
echo "$SWAY_PID" > "$RUN/sway.pid"
[[ -S "$SWAYSOCK_PATH" ]] || die "sway IPC socket never appeared; see $RUN/sway.log"

# Sway picks its wayland socket with wl_display_add_socket_auto() and offers no
# flag to force one. Reading /proc/$SWAY_PID/environ does not work either: sway
# sets PR_SET_DUMPABLE=0, which reparents those /proc entries to root. So ask
# sway to tell us, by running a child through its own IPC and having that child
# report the environment it inherited.
WD_FILE="$RUN/.wd"
rm -f "$WD_FILE"
SWAYSOCK="$SWAYSOCK_PATH" swaymsg -q exec -- \
    "sh -c 'printf %s \"\$WAYLAND_DISPLAY\" > $(printf '%q' "$WD_FILE")'"
for _ in $(seq 1 40); do
    [[ -s "$WD_FILE" ]] && break
    sleep 0.1
done
WD="$(cat "$WD_FILE" 2>/dev/null || true)"
rm -f "$WD_FILE"
[[ -n "$WD" ]] || die "could not determine sway's WAYLAND_DISPLAY"
echo "$WD" > "$RUN/wayland_display"
echo ":: sway up on \$WAYLAND_DISPLAY=$WD (ipc $SWAYSOCK_PATH)"

SWAYSOCK="$SWAYSOCK_PATH" swaymsg -q \
    "output HEADLESS-1 mode ${W}x${H}@60Hz scale ${SCALE}" \
    || die "failed to set headless output mode"

# --- wayvnc -----------------------------------------------------------------
echo ":: starting wayvnc on ${BIND}:${PORT}"
WAYLAND_DISPLAY="$WD" \
    setsid wayvnc \
        --config "$DIR/wayvnc.conf" \
        --socket "$VNCSOCK_PATH" \
        --output HEADLESS-1 \
        --max-fps "$FPS" \
        --render-cursor \
        --disable-resizing \
        "$BIND" "$PORT" >"$RUN/wayvnc.log" 2>&1 &

for _ in $(seq 1 40); do
    if ss -ltn 2>/dev/null | grep -q ":${PORT}\b"; then break; fi
    sleep 0.2
done
VNC_PID="$(pid_by_marker "$VNCSOCK_PATH" || true)"
[[ -n "$VNC_PID" ]] || { cat "$RUN/wayvnc.log" >&2; die "wayvnc did not start"; }
echo "$VNC_PID" > "$RUN/wayvnc.pid"
ss -ltn 2>/dev/null | grep -q ":${PORT}\b" || { cat "$RUN/wayvnc.log" >&2; die "wayvnc never bound ${BIND}:${PORT}"; }

cat <<EOF

  second screen is up
  ----------------------------------------------------------
  connect from the iPad VNC client to   ${BIND}:${PORT}
  framebuffer                           ${W}x${H} (scale ${SCALE})
  launch an app onto it                 ./screen-run.sh <command>
  tear it down                          ./screen-down.sh
EOF
