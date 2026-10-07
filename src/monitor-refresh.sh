#!/bin/bash
#
# monitor-refresh.sh - Switch DP-1 monitor refresh rate between 240Hz and 120Hz.
#
# Designed as a LACT profile hook: run with "on" when a game profile
# activates and "off" when it deactivates. When executed as root
# (lactd), it picks up the desktop session environment automatically.
#
# Usage:  monitor-refresh.sh 240   -> switch to 240Hz
#         monitor-refresh.sh 120   -> switch to 120Hz
#         monitor-refresh.sh       -> print the current refresh rate
#
set -euo pipefail

# Configuration
OUTPUT="DP-1"
MODE_GAME="3840x2160@240"
MODE_IDLE="3840x2160@120"
SESSION_USER="bubba"

usage() {
    echo "usage: $(basename "$0") {120|240}" >&2
    exit "${1:-1}"
}

current_refresh() {
    kscreen-doctor -o 2>/dev/null |
        sed 's/\x1b\[[0-9;]*m//g' |
        awk -v out="$OUTPUT" '
            /^Output:/ { inblock = ($0 ~ (" " out " ")) }
            inblock && match($0, /@[0-9.]+\*/) {
                rate = substr($0, RSTART + 1, RLENGTH - 2)
                printf "%.0f\n", rate
                exit
            }
        ' || true
}

case "${1:-}" in
    240) MODE="$MODE_GAME" ;;
    120) MODE="$MODE_IDLE" ;;
    "")
        rate=$(current_refresh)
        if [ -n "$rate" ]; then
            echo "$OUTPUT: $rate Hz"
        else
            echo "$OUTPUT: refresh rate unavailable" >&2
        fi
        usage 0
        ;;
    *) usage ;;
esac

# lactd runs as root; kscreen-doctor needs the desktop session environment
if [ "$(id -u)" -eq 0 ]; then
    uid=$(id -u "$SESSION_USER")
    export XDG_RUNTIME_DIR="/run/user/$uid"
    export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"

    # Pick the graphical session, skipping the user-manager session (type
    # "unspecified"), which otherwise wins an alphabetical sort.
    session_type=""
    while read -r s; do
        t=$(loginctl show-session "$s" -p Type --value 2>/dev/null || true)
        case "$t" in
            wayland|x11) session_type="$t"; break ;;
        esac
    done < <(loginctl --no-legend list-sessions 2>/dev/null | awk -v u="$SESSION_USER" '$3 == u {print $1}')

    case "$session_type" in
        wayland) export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}" ;;
        x11)     export DISPLAY="${DISPLAY:-:0}" ;;
    esac
fi

exec kscreen-doctor output."$OUTPUT".mode."$MODE"
