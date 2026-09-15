#!/bin/bash
# Complete teardown: stop the screen, remove the five packages this
# experiment added, and delete all generated state.
#
# Packages removed: sway swaybg wayvnc neatvnc aml
# Nothing else on the system was modified -- no services, no kernel
# parameters, no files outside this directory.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$DIR/niri-screen-down.sh"
"$DIR/screen-down.sh"

echo
echo "About to remove: sway swaybg wayvnc neatvnc aml"
read -r -p "Proceed? [y/N] " ans
[[ "$ans" == [yY] ]] || { echo "aborted"; exit 0; }

# shellcheck disable=SC1090
. ~/.secrets >/dev/null 2>&1
printf '%s\n' "${SUDO_PWD:-}" | sudo -S -p '' xbps-remove -Roy sway swaybg wayvnc neatvnc aml

rm -rf "$DIR/run" "$DIR/xdg"
echo ":: removed generated state under $DIR"
echo ":: remaining files are the scripts and configs themselves; rm -rf $DIR to finish"
