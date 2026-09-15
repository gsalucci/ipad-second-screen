#!/bin/bash
# Fetch noVNC into vendor/. Not committed: it is a third-party project with its
# own licence, and pinning a tarball here would just be a stale copy of upstream.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VER="${NOVNC_VERSION:-1.6.0}"

mkdir -p "$DIR/vendor"
if [[ -f "$DIR/vendor/novnc/vnc.html" ]]; then
    echo ":: noVNC already present at vendor/novnc"
    exit 0
fi
echo ":: fetching noVNC v${VER}"
curl -fsSL --max-time 180 -o "$DIR/vendor/novnc.tar.gz" \
    "https://github.com/novnc/noVNC/archive/refs/tags/v${VER}.tar.gz"
tar xzf "$DIR/vendor/novnc.tar.gz" -C "$DIR/vendor"
mv "$DIR/vendor/noVNC-${VER}" "$DIR/vendor/novnc"
rm -f "$DIR/vendor/novnc.tar.gz"
echo ":: noVNC v${VER} unpacked at vendor/novnc"
