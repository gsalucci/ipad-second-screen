# Creating and removing the virtual output.
#
# The kernel lets you force a disconnected DRM connector on, and lets you hand
# it an EDID that no cable ever carried:
#
#     echo on > /sys/class/drm/<card>-<conn>/status
#     cat edid.bin > /sys/kernel/debug/dri/<n>/<conn>/edid_override
#
# The compositor then sees an ordinary monitor. Both writes are runtime only --
# nothing is persisted, and a reboot removes every trace.

display_check() {
    [[ -e "$SYS/status" ]] || die "no such connector: $SYS"
    [[ -n "${WAYLAND_DISPLAY:-}" ]] || die "WAYLAND_DISPLAY unset -- run this inside the niri session"
    command -v niri >/dev/null || die "niri not found"

    # An EDID with no CEA-861 extension block makes the driver treat the
    # connector as DVI and apply the 165 MHz single-link ceiling. 2160x1620@60
    # needs 232 MHz, so it is rejected on HDMI and accepted on DisplayPort.
    case "$CONN" in
        HDMI*) warn "$CONN is HDMI: the 165 MHz DVI limit will reject ${W}x${H}@${R}."
               warn "Use a DisplayPort connector, or lower R to about 40." ;;
    esac
}

display_up() {
    local edid="$RUN/edid-${W}x${H}.bin"
    EW="$W" EH="$H" ER="$R" python3 "$ROOT/mkedid.py" "$edid" >/dev/null
    say "generated EDID ${W}x${H}@${R}"

    say "forcing $CONN on"
    as_root sh -c "
        echo detect > '$SYS/status'
        cat '$edid' > '$DBG/edid_override'
        echo on > '$SYS/status'
    " || die "could not force the connector (is debugfs mounted?)"

    wait_for 25 grep -qx "${W}x${H}" "$SYS/modes" || {
        echo "modes offered: $(tr '\n' ' ' < "$SYS/modes")" >&2
        die "the driver rejected ${W}x${H} -- see the DisplayPort note in the README"
    }
    say "$CONN is $(cat "$SYS/status"), offering ${W}x${H}"

    say "placing it at ${POS_X},${POS_Y} scale ${SCALE}"
    niri msg output "$CONN" on                            >/dev/null
    niri msg output "$CONN" mode "${W}x${H}@${R}.000"     >/dev/null || \
        niri msg output "$CONN" mode "${W}x${H}"          >/dev/null
    niri msg output "$CONN" scale "$SCALE"                >/dev/null
    niri msg output "$CONN" position set "$POS_X" "$POS_Y" >/dev/null
}

display_down() {
    [[ -e "$SYS/status" ]] || return 0
    as_root sh -c "echo detect > '$SYS/status'" 2>/dev/null || return 0
    sleep 1
    say "released $CONN (now $(cat "$SYS/status"))"
}
