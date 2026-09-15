# The VNC server. One wayvnc bound to the LAN address, capturing the virtual
# output. RFB carries no transport encryption here, so it binds $BIND
# specifically and never 0.0.0.0.

vnc_up() {
    say "starting wayvnc on ${BIND}:${PORT}"
    setsid wayvnc \
        --config "$ROOT/wayvnc.conf" \
        --socket "$VNC_SOCK" \
        --output "$CONN" \
        --max-fps "$FPS" \
        --render-cursor \
        --disable-resizing \
        "$BIND" "$PORT" >"$VNC_LOG" 2>&1 &

    wait_for 40 port_listening "$PORT" || { cat "$VNC_LOG" >&2; die "wayvnc never bound ${BIND}:${PORT}"; }

    local pid
    pid="$(pid_by_marker "$VNC_SOCK" || true)"
    [[ -n "$pid" ]] || { cat "$VNC_LOG" >&2; die "wayvnc did not start"; }
    echo "$pid" > "$VNC_PID"
}

vnc_down() {
    stop_pidfile wayvnc "$VNC_PID" "$VNC_SOCK"
    rm -f "$VNC_SOCK"
}
