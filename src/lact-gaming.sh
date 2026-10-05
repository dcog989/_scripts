#!/bin/bash
#
# lact-gaming.sh - LACT "Gaming" profile hook: switch the DP-1 refresh rate and
# park clipboard/backup tray apps while a game is running.
#
# On activation the monitor drops to its game mode and any running cliptoo /
# KopiaUI instances are recorded (so they can be restored later) then stopped.
# On deactivation the monitor returns to idle and only the apps that were
# running at activation are started again.
#
# Designed to run as root from lactd; it enters the desktop session user's
# environment to reach the Wayland/X11 session.
#
# Usage:  lact-gaming.sh on    -> 240Hz, stop cliptoo and KopiaUI
#         lact-gaming.sh off   -> 120Hz, restart previously stopped apps
#
set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SESSION_USER="${SESSION_USER:-bubba}"
REFRESH_SCRIPT="$SCRIPT_DIR/monitor-refresh.sh"
MODE_GAME="240"
MODE_IDLE="120"
APPS=(cliptoo kopia-ui)

usage() {
    echo "usage: $(basename "$0") {on|off}" >&2
    exit "${1:-1}"
}

log() { printf '%s lact-gaming: %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >&2; }

# Enter the desktop session environment when invoked by lactd (root).
setup_session_env() {
    [ "$(id -u)" -eq 0 ] || return 0

    local uid session_type=""
    uid=$(id -u "$SESSION_USER")
    export XDG_RUNTIME_DIR="/run/user/$uid"
    export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"

    # Pick the graphical session, skipping the user-manager session (type
    # "unspecified"), which otherwise wins an alphabetical sort.
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
    export XDG_SESSION_TYPE="$session_type"
}

state_dir() {
    local home
    if [ "$(id -u)" -eq 0 ]; then
        home=$(getent passwd "$SESSION_USER" | cut -d: -f6)
    else
        home="$HOME"
    fi
    printf '%s\n' "${XDG_STATE_HOME:-$home/.local/state}/lact-gaming"
}

chown_to_user() {
    [ "$(id -u)" -eq 0 ] && chown "$SESSION_USER" "$1" 2>/dev/null || true
}

is_running() {
    case "$1" in
        cliptoo)  pgrep -u "$SESSION_USER" -x cliptoo >/dev/null 2>&1 ;;
        kopia-ui) pgrep -u "$SESSION_USER" -f '/opt/KopiaUI/kopia-ui' >/dev/null 2>&1 ;;
    esac
}

# _stop <pkill match args...>
_stop() {
    pkill -TERM -u "$SESSION_USER" "$@" 2>/dev/null || return 0
    local i=0
    while pgrep -u "$SESSION_USER" "$@" >/dev/null 2>&1; do
        i=$((i + 1))
        if [ "$i" -ge 50 ]; then
            pkill -KILL -u "$SESSION_USER" "$@" 2>/dev/null || true
            break
        fi
        sleep 0.1
    done
}

stop_app() {
    case "$1" in
        cliptoo)  _stop -x cliptoo ;;
        kopia-ui) _stop -f '/opt/KopiaUI/' ;;
    esac
}

# _launch <binary> - detach the app into the user's graphical session.
_launch() {
    local uid env_args
    uid=$(id -u "$SESSION_USER")
    env_args=(
        "XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$uid}"
        "DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/$uid/bus}"
    )
    [ -n "${DISPLAY:-}" ]          && env_args+=("DISPLAY=$DISPLAY")
    [ -n "${WAYLAND_DISPLAY:-}" ]  && env_args+=("WAYLAND_DISPLAY=$WAYLAND_DISPLAY")
    [ -n "${XDG_SESSION_TYPE:-}" ] && env_args+=("XDG_SESSION_TYPE=$XDG_SESSION_TYPE")

    if [ "$(id -u)" -eq 0 ]; then
        runuser -u "$SESSION_USER" -- env "${env_args[@]}" setsid --fork "$1" >/dev/null 2>&1
    else
        setsid --fork "$1" >/dev/null 2>&1
    fi
}

start_app() {
    case "$1" in
        cliptoo)  _launch /usr/local/bin/cliptoo ;;
        kopia-ui) _launch /opt/KopiaUI/kopia-ui ;;
    esac
}

set_refresh() {
    if [ ! -x "$REFRESH_SCRIPT" ]; then
        log "refresh script not found: $REFRESH_SCRIPT"
        return 0
    fi
    "$REFRESH_SCRIPT" "$1" || log "refresh switch to ${1}Hz failed"
}

activate() {
    set_refresh "$MODE_GAME"

    local dir file app
    dir=$(state_dir)
    file="$dir/active-apps"
    mkdir -p "$dir"
    chown_to_user "$dir"
    touch "$file"

    for app in "${APPS[@]}"; do
        is_running "$app" || continue
        grep -qxF "$app" "$file" || printf '%s\n' "$app" >> "$file"
        log "stopping $app"
        stop_app "$app"
    done
    chown_to_user "$file"
}

deactivate() {
    set_refresh "$MODE_IDLE"

    local dir file app
    dir=$(state_dir)
    file="$dir/active-apps"
    [ -f "$file" ] || return 0

    while IFS= read -r app; do
        [ -n "$app" ] || continue
        if is_running "$app"; then
            log "$app already running, skipping"
        else
            log "starting $app"
            start_app "$app"
        fi
    done < "$file"
    rm -f "$file"
}

case "${1:-}" in
    on)  setup_session_env; activate ;;
    off) setup_session_env; deactivate ;;
    *)   usage ;;
esac
