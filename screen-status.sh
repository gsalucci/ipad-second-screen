#!/bin/bash
# Report whether the iPad second screen is up, and what is on it.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN="$DIR/run"

alive() { [[ -f "$1" ]] && kill -0 "$(cat "$1")" 2>/dev/null; }

for p in sway wayvnc; do
    if alive "$RUN/$p.pid"; then
        pid="$(cat "$RUN/$p.pid")"
        printf '%-8s up    pid %-7s %s\n' "$p" "$pid" \
            "$(ps -o pcpu=,rss= -p "$pid" 2>/dev/null | awk '{printf "%.1f%% cpu, %d MiB", $1, $2/1024}')"
    else
        printf '%-8s down\n' "$p"
    fi
done

[[ -f "$RUN/wayland_display" ]] && echo "display  \$WAYLAND_DISPLAY=$(cat "$RUN/wayland_display")"
ss -ltn 2>/dev/null | awk '/:5900/ {print "listen   " $4}'

if [[ -S "$RUN/sway-ipc.sock" ]]; then
    SWAYSOCK="$RUN/sway-ipc.sock" swaymsg -t get_tree 2>/dev/null | python3 -c '
import json, sys
def walk(n, out):
    if n.get("pid"): out.append((n.get("app_id") or n.get("name"), n["rect"]))
    for c in n.get("nodes", []) + n.get("floating_nodes", []): walk(c, out)
out = []
walk(json.load(sys.stdin), out)
print("windows  %d" % len(out))
for name, r in out:
    print("         %s  %dx%d+%d+%d" % (name, r["width"], r["height"], r["x"], r["y"]))
'
fi
