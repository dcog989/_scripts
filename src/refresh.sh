#!/bin/bash
#
# refresh.sh - Switch DP-1 monitor refresh rate between 240Hz and 120Hz.
#
# Designed as a LACT profile hook: run with "on" when a game profile
# activates and "off" when it deactivates. When executed as root
# (lactd), it picks up the desktop session environment automatically.
#
# Usage:  refresh.sh 240   -> switch to 240Hz
#         refresh.sh 120   -> switch to 120Hz
#
set -euo pipefail

# Configuration
OUTPUT="DP-1"
MODE_GAME="3840x2160@240"
MODE_IDLE="3840x2160@120"
SESSION_USER="bubba"

usage() {
    echo "usage: $0 {120|240}" >&2
    exit 1
}

case "${1:-}" in
    240) MODE="$MODE_GAME" ;;
    120) MODE="$MODE_IDLE" ;;
    *) usage ;;
esac

# lactd runs as root; kscreen-doctor needs the desktop session environment
if [ "$(id -u)" -eq 0 ]; then
    uid=$(id -u "$SESSION_USER")
    export XDG_RUNTIME_DIR="/run/user/$uid"
    export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"

    session_type=$(loginctl --no-legend list-sessions |
        awk -v u="$SESSION_USER" '$3 == u {print $1}' |
        while read -r s; do loginctl show-session "$s" -p Type --value; done |
        sort -u | head -1)
    case "$session_type" in
        wayland) export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}" ;;
        x11)     export DISPLAY="${DISPLAY:-:0}" ;;
    esac
fi

exec kscreen-doctor output."$OUTPUT".mode."$MODE"
