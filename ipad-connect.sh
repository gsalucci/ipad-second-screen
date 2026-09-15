#!/bin/bash
# Tell the iPad to open RealVNC Viewer against this host.
#
# RealVNC registers the `vnc://` URL scheme (verified in its Info.plist:
# com.realvnc.VNCViewer 4.9.4, CFBundleURLSchemes = ["vnc"]), and the jailbreak
# ships `uiopen`, so one SSH call is enough -- no UI automation, no WebDriverAgent.
#
# The `--url` flag is REQUIRED. `uiopen 'vnc://...'` with the URL as a bare
# argument exits 0 and launches VNC Viewer, but silently drops the URL: the app
# comes up on its address book having never seen it. That failure looks exactly
# like a broken URL scheme, which it is not -- the binary contains the format
# string `vnc://%@:%ld`.
#
# This runs over **Wi-Fi**, not the USB port-forward the rest of tools/ uses:
# the iPad's sshd listens on all interfaces, so no cable is required.
#
#   ./ipad-connect.sh              # connect to the default 5901
#   PORT=5900 ./ipad-connect.sh    # the rung 1 headless screen instead
#   IPAD_HOST=10.0.0.42 ./ipad-connect.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Host-specific values live in .env (see .env.example); it is gitignored.
[[ -f "$DIR/.env" ]] && . "$DIR/.env"
RUN="$DIR/run"; mkdir -p "$RUN"
HOST_IP="${HOST_IP:-}"
PORT="${PORT:-5901}"
WS_PORT="${WS_PORT:-5902}"
WEB_PORT="${WEB_PORT:-6080}"
# vnc  = RealVNC Viewer (default). Native, ~19 Mbit/s, and genuinely full screen:
#        it hides the iPad status bar and the 4:3 framebuffer maps 1:1 onto the
#        4:3 panel with no letterboxing. Cost is one "Continue connecting?" tap
#        per *pushed* URL -- that dialog has no suppress option (verified in the
#        binary: dialog_connect_url_{title,body,button_ok,button_cancel} exist,
#        nothing like a "don't ask again" flag does). Note the tap is only for a
#        push: if RealVNC is already sitting open it reconnects by itself and
#        niri-screen-up.sh never calls this script at all.
# web  = noVNC in the SecondScreen Home Screen web app. Connects with no
#        confirmation ever, but a web app cannot hide the iPad status bar, so the
#        usable viewport is no longer exactly 4:3 and the image letterboxes.
CLIENT="${CLIENT:-vnc}"
KEY="${KEY:-$HOME/.ssh/id_ed25519_ipad}"
[[ -n "${HOST_IP:-}" ]] || { echo "error: HOST_IP is not set -- copy .env.example to .env" >&2; exit 1; }
CACHE="$RUN/ipad-host"
# iOS uses a private (locally-administered) Wi-Fi MAC that can rotate, so the MAC
# is a hint for the ARP fallback, not an identity. The cached IP is tried first.
IPAD_MAC="${IPAD_MAC:-}"

SSH=(ssh -i "$KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
     -o LogLevel=ERROR -o BatchMode=yes -o ConnectTimeout=4)

reachable() {  # $1 = ip -- proves it is *our* iPad, not just something with sshd
    timeout 8 "${SSH[@]}" "mobile@$1" 'test -x /var/jb/usr/bin/uiopen' 2>/dev/null
}

find_ipad() {
    local ip
    if [[ -n "${IPAD_HOST:-}" ]]; then
        reachable "$IPAD_HOST" && { echo "$IPAD_HOST"; return 0; }
        return 1
    fi
    ip="$(cat "$CACHE" 2>/dev/null)"
    if [[ -n "$ip" ]] && reachable "$ip"; then echo "$ip"; return 0; fi
    ip="$(ip neigh show 2>/dev/null | awk -v m="$IPAD_MAC" '$0 ~ m {print $1; exit}')"
    if [[ -n "$ip" ]] && reachable "$ip"; then echo "$ip"; return 0; fi
    # Last resort: whoever on this /24 answers on 22 and has uiopen.
    local base; base="$(printf '%s' "$HOST_IP" | cut -d. -f1-3)"
    for i in $(seq 2 254); do
        (timeout 1 bash -c "exec 3<>/dev/tcp/$base.$i/22" 2>/dev/null && echo "$base.$i") &
    done >"$RUN/.sweep" 2>/dev/null
    wait
    while read -r ip; do
        reachable "$ip" && { echo "$ip"; rm -f "$RUN/.sweep"; return 0; }
    done < "$RUN/.sweep"
    rm -f "$RUN/.sweep"
    return 1
}

IP="$(find_ipad)" || {
    echo "ipad-connect: iPad not reachable over Wi-Fi (asleep, off the network," >&2
    echo "              or its address changed). The screen is up regardless --" >&2
    echo "              connect RealVNC by hand to ${HOST_IP}:${PORT}." >&2
    exit 1
}
echo "$IP" > "$CACHE"

# Why there is no "launch the Home Screen web app" branch here.
#
# iOS 18 installs a Home Screen web app as a real bundle under
# /var/containers/Bundle/Application, but it has NO executable and its
# Info.plist carries LSApplicationLaunchProhibited=true. Every LaunchServices
# route refuses it -- `uiopen --bundleid`, `--app` and `--path` all exit 0 and do
# nothing, and `uicache -i` reports `Executable Name: (null)`. Removing the flag
# and re-registering does not help either (tested, then reverted): the bundle
# still has no executable, and SpringBoard launches these through its own API
# that no on-device CLI exposes. Shortcuts cannot bridge it either -- its
# "Open App" picker uses the same LaunchServices filter and does not list web
# apps.
#
# So the web app cannot be started remotely. It does not need to be: leave it
# open on the iPad and noVNC's own reconnect brings it back whenever wayvnc
# returns. niri-screen-up.sh waits for that and only calls this script if the
# iPad did NOT come back by itself -- in which case Safari (below) is the right
# answer anyway, since the web app clearly is not running.

if [[ "$CLIENT" == "web" ]]; then
    # autoconnect makes noVNC dial straight out; path= is empty because wayvnc
    # accepts the WebSocket upgrade on "/" rather than noVNC's default
    # "/websockify"; reconnect brings it back by itself after a toggle.
    URL="http://${HOST_IP}:${WEB_PORT}/vnc.html?host=${HOST_IP}&port=${WS_PORT}"
    URL="${URL}&path=&autoconnect=true&reconnect=true&reconnect_delay=2000"
    # resize=scale, not remote: wayvnc runs with --disable-resizing, so asking the
    # server to match the browser viewport does nothing and leaves a 2160x1620
    # canvas to scroll around. scale fits it to the iPad screen client-side.
    URL="${URL}&resize=scale&quality=6&compression=2"
else
    URL="vnc://${HOST_IP}:${PORT}"
fi

if timeout 10 "${SSH[@]}" "mobile@$IP" \
     "export PATH=/var/jb/usr/bin:/var/jb/bin:\$PATH; uiopen --url '${URL}'" 2>/dev/null
then
    echo ":: asked the iPad ($IP) to open ${URL}"
else
    echo "ipad-connect: uiopen failed on $IP" >&2
    exit 1
fi
