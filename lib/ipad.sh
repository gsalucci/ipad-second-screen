# Telling the iPad to connect.
#
# A jailbroken iPad runs sshd on every interface, so this works over Wi-Fi with
# no cable. `uiopen --url` hands a URL to the device's URL handlers, and RealVNC
# Viewer registers the vnc:// scheme.
#
# The --url flag is required. With the URL as a bare argument uiopen exits 0 and
# launches the app without ever delivering the URL.

IPAD_KEY="${IPAD_KEY:-$HOME/.ssh/id_ed25519_ipad}"
IPAD_CACHE="$RUN/ipad-host"

# `timeout` cannot run a shell function, so the bound goes inside: ssh's own
# ConnectTimeout plus a hard ceiling via its command line.
_ssh() {
    timeout 12 ssh -i "$IPAD_KEY" \
        -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR -o BatchMode=yes \
        -o ConnectTimeout=5 -o ConnectionAttempts=1 "$@"
}

# Confirm a candidate is really the tablet, not just some host running sshd.
_is_ipad() { _ssh "mobile@$1" 'test -x /var/jb/usr/bin/uiopen' 2>/dev/null; }

# iOS uses a private, rotatable Wi-Fi MAC, so IPAD_MAC is a hint and not an
# identity. Order: explicit setting, last known good, ARP table, /24 sweep.
ipad_find() {
    local ip base i
    if [[ -n "${IPAD_HOST:-}" ]]; then
        _is_ipad "$IPAD_HOST" && { echo "$IPAD_HOST"; return 0; }
        return 1
    fi
    ip="$(cat "$IPAD_CACHE" 2>/dev/null || true)"
    [[ -n "$ip" ]] && _is_ipad "$ip" && { echo "$ip"; return 0; }

    if [[ -n "${IPAD_MAC:-}" ]]; then
        ip="$(ip neigh show 2>/dev/null | awk -v m="$IPAD_MAC" '$0 ~ m {print $1; exit}')"
        [[ -n "$ip" ]] && _is_ipad "$ip" && { echo "$ip"; return 0; }
    fi

    base="$(printf '%s' "$BIND" | cut -d. -f1-3)"
    # Wait on THESE pids only. A bare `wait` also waits on the jobs table, which
    # still holds the wayvnc job started earlier in this run; setsid reparented
    # it, so bash spins on "not a child of this shell" and never returns.
    local pids=()
    for i in $(seq 2 254); do
        (timeout 1 bash -c "exec 3<>/dev/tcp/$base.$i/22" 2>/dev/null && echo "$base.$i") &
        pids+=("$!")
    done >"$RUN/.sweep" 2>/dev/null
    wait "${pids[@]}" 2>/dev/null || true
    while read -r ip; do
        _is_ipad "$ip" && { echo "$ip"; rm -f "$RUN/.sweep"; return 0; }
    done < "$RUN/.sweep"
    rm -f "$RUN/.sweep"
    return 1
}

ipad_connect() {
    local ip url
    ip="$(ipad_find)" || {
        warn "iPad not reachable (asleep, off the network, or its address changed)."
        warn "The screen is up regardless -- connect by hand to ${BIND}:${PORT}."
        return 1
    }
    echo "$ip" > "$IPAD_CACHE"

    url="vnc://${BIND}:${PORT}"
    if _ssh "mobile@$ip" \
         "export PATH=/var/jb/usr/bin:/var/jb/bin:\$PATH; uiopen --url '$url'" 2>/dev/null
    then
        say "asked the iPad ($ip) to open $url"
        say "confirm the \"Continue connecting?\" prompt on the tablet"
    else
        warn "uiopen failed on $ip"
        return 1
    fi
}

# A client that is already open reconnects by itself once wayvnc is listening
# again; pushing a URL in that case would only interrupt it. Wait first.
ipad_autoconnect() {
    [[ "$AUTOCONNECT" == "1" ]] || return 0
    local i
    for ((i = 0; i < AUTOCONNECT_WAIT; i++)); do
        if port_has_client "$PORT"; then
            say "the iPad reconnected on its own"
            return 0
        fi
        sleep 1
    done
    ipad_connect || true
}
