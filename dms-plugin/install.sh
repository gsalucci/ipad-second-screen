#!/bin/bash
# Install the DankBar toggle button into DankMaterialShell.
#
# Adds the plugin, enables it, and inserts it into the bar's right-hand widgets.
# Existing settings files are backed up next to themselves first.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLDIR="$(cd "$SRC/.." && pwd)"
DEST="${XDG_CONFIG_HOME:-$HOME/.config}/DankMaterialShell"
[[ -d "$DEST" ]] || { echo "DankMaterialShell config not found at $DEST" >&2; exit 1; }

mkdir -p "$DEST/plugins/ipadScreen"
cp "$SRC/plugin.json" "$DEST/plugins/ipadScreen/"
sed "s#@TOOLDIR@#$TOOLDIR#" "$SRC/IpadScreenWidget.qml" > "$DEST/plugins/ipadScreen/IpadScreenWidget.qml"
echo ":: installed plugin -> $DEST/plugins/ipadScreen (toolDir=$TOOLDIR)"

python3 - "$DEST" <<'PY'
import json, pathlib, shutil, sys, time

dest = pathlib.Path(sys.argv[1])

ps = dest / "plugin_settings.json"
if ps.exists():
    shutil.copy(ps, f"{ps}.bak-{int(time.time())}")
    d = json.loads(ps.read_text())
else:
    d = {}
d.setdefault("ipadScreen", {})["enabled"] = True
ps.write_text(json.dumps(d, indent=2))
print(":: enabled in plugin_settings.json")

st = dest / "settings.json"
if not st.exists():
    print(":: settings.json not found; add the widget to the bar by hand")
    raise SystemExit
shutil.copy(st, f"{st}.bak-{int(time.time())}")
s = json.loads(st.read_text())
bars = s.get("barConfigs") or []
if not bars:
    print(":: no barConfigs; add the widget to the bar by hand")
    raise SystemExit
rw = bars[0].setdefault("rightWidgets", [])
if any(isinstance(w, dict) and w.get("id") == "ipadScreen" for w in rw):
    print(":: already present in the bar")
else:
    rw.insert(0, {"id": "ipadScreen", "enabled": True})
    st.write_text(json.dumps(s, indent=1))
    print(":: inserted into barConfigs[0].rightWidgets")
PY

cat <<'EOF2'

Reload DMS to pick it up. Do NOT use `dms restart`: it re-execs itself as
`dms run -d --daemon-child`, and if a session supervisor also respawns its own
`dms run` you end up with two shells and two stacked bars. Kill the supervised
process instead and let the supervisor bring it back:

    pkill -x dms     # or kill the `dms run` whose parent is your session script
EOF2
