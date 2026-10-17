#!/bin/bash
#
# lact-gaming.sh - LACT "Gaming" profile hook: switch the DP-1 refresh rate and
# park clipboard/backup tray apps while a game is running.
#
# On activation the refresh mode active beforehand is recorded, any running
# cliptoo / KopiaUI instances are recorded (so they can be restored later) then
# stopped, and finally the monitor drops to its game mode. On deactivation the
# monitor returns to the recorded mode and only the apps that were running at
# activation are started again.
#
# State lives in ${XDG_STATE_HOME:-$HOME/.local/state}/lact-gaming/state and
# doubles as the "profile is active" marker: if it already exists when `on`
# runs (e.g. `off` never fired after a crash), the recorded state is preserved
# instead of overwritten, so `off` still restores the right values.
#
# Designed to run as root from lactd; it enters the desktop session user's
# environment to reach the Wayland/X11 session.
#
# Usage:  lact-gaming.sh on    -> 240Hz, stop cliptoo and KopiaUI
#         lact-gaming.sh off   -> restore recorded mode, restart stopped apps
#
set -euo pipefail

# Configuration
SESSION_USER="${SESSION_USER:-bubba}"
OUTPUT="DP-1"
MODE_GAME="3840x2160@240"
MODE_IDLE="3840x2160@120"
STOP_TRIES=50
STOP_INTERVAL=0.1

# App table: app name -> pgrep/pkill match flag, match pattern, launch command.
declare -A APP_MATCH_FLAG=(
    [cliptoo]='-x'
    [kopia-ui]='-f'
)
declare -A APP_MATCH_PATTERN=(
    [cliptoo]='cliptoo'
    [kopia-ui]='/opt/KopiaUI/'
)
declare -A APP_COMMAND=(
    [cliptoo]='/usr/local/bin/cliptoo'
    [kopia-ui]='/opt/KopiaUI/kopia-ui'
)
APPS=(cliptoo kopia-ui)

usage() {
    echo "usage: $(basename "$0") {on|off}" >&2
    exit "${1:-1}"
}

log() { printf '%s lact-gaming: %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >&2; }

# Enter the desktop session environment when invoked by lactd (root).
setup_session_env() {
    [ "$(id -u)" -eq 0 ] || return 0

    local uid session_type="" s t seat active fallback=""
    uid=$(id -u "$SESSION_USER")
    export XDG_RUNTIME_DIR="/run/user/$uid"
    export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"

    # Pick the graphical session. Require a seat so per-application scope
    # sessions (seat=none, type inherited from the environment) are skipped,
    # and prefer an active one; fall back to the first wayland/x11 session.
    while read -r s; do
        t=$(loginctl show-session "$s" -p Type --value 2>/dev/null || true)
        case "$t" in
            wayland|x11) ;;
            *) continue ;;
        esac
        [ -n "$fallback" ] || fallback="$t"
        seat=$(loginctl show-session "$s" -p Seat --value 2>/dev/null || true)
        active=$(loginctl show-session "$s" -p Active --value 2>/dev/null || true)
        if [ -n "$seat" ] && [ "$active" = "yes" ]; then
            session_type="$t"
            break
        fi
    done < <(loginctl --no-legend list-sessions 2>/dev/null | awk -v u="$SESSION_USER" '$3 == u {print $1}')
    [ -n "$session_type" ] || session_type="$fallback"

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
    pgrep -u "$SESSION_USER" "${APP_MATCH_FLAG[$1]}" -- "${APP_MATCH_PATTERN[$1]}" >/dev/null 2>&1
}

# _stop <match flag> <match pattern>
_stop() {
    local flag="$1" pattern="$2" i=0
    pkill -TERM -u "$SESSION_USER" "$flag" -- "$pattern" 2>/dev/null || return 0
    while pgrep -u "$SESSION_USER" "$flag" -- "$pattern" >/dev/null 2>&1; do
        i=$((i + 1))
        if [ "$i" -ge "$STOP_TRIES" ]; then
            pkill -KILL -u "$SESSION_USER" "$flag" -- "$pattern" 2>/dev/null || true
            break
        fi
        sleep "$STOP_INTERVAL"
    done
}

stop_app() {
    _stop "${APP_MATCH_FLAG[$1]}" "${APP_MATCH_PATTERN[$1]}"
}

# session_env_source - PID of a long-lived process carrying the desktop session
# environment, or nothing. Login and per-app scope sessions do not expose it, so
# read it from a desktop process instead.
session_env_source() {
    local cmd pid
    for cmd in plasmashell kwin_wayland kwin_x11 ksmserver kded6; do
        pid=$(pgrep -u "$SESSION_USER" -x "$cmd" 2>/dev/null | head -1) || true
        if [ -n "$pid" ] && grep -qz '^XDG_CURRENT_DESKTOP=' "/proc/$pid/environ" 2>/dev/null; then
            printf '%s\n' "$pid"
            return 0
        fi
    done
    return 1
}

# _launch <binary> - detach the app into the user's graphical session, reusing
# the desktop environment so toolkits load the KDE platform theme.
_launch() {
    local uid src
    local -a env_args=()

    uid=$(id -u "$SESSION_USER")

    src=$(session_env_source || true)
    if [ -n "$src" ]; then
        mapfile -d '' -t env_args < "/proc/$src/environ" || true
    else
        env_args=(
            # the apps are absolute paths, but anything they spawn needs a PATH
            "PATH=/usr/local/bin:/usr/bin"
            "XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$uid}"
            "DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/$uid/bus}"
        )
        [ -n "${DISPLAY:-}" ]          && env_args+=("DISPLAY=$DISPLAY")
        [ -n "${WAYLAND_DISPLAY:-}" ]  && env_args+=("WAYLAND_DISPLAY=$WAYLAND_DISPLAY")
        [ -n "${XDG_SESSION_TYPE:-}" ] && env_args+=("XDG_SESSION_TYPE=$XDG_SESSION_TYPE")
    fi

    if [ "$(id -u)" -eq 0 ]; then
        runuser -u "$SESSION_USER" -- env -i "${env_args[@]}" setsid --fork "$1" >/dev/null 2>&1
    else
        env -i "${env_args[@]}" setsid --fork "$1" >/dev/null 2>&1
    fi
}

start_app() {
    _launch "${APP_COMMAND[$1]}"
}

# current_mode - print the active DP-1 mode (e.g. 3840x2160@120), or nothing.
current_mode() {
    kscreen-doctor -o 2>/dev/null |
        sed 's/\x1b\[[0-9;]*m//g' |
        awk -v out="$OUTPUT" '
            /^Output:/ { inblock = ($0 ~ (" " out " ")) }
            inblock && match($0, /[0-9]+x[0-9]+@[0-9.]+\*/) {
                tok = substr($0, RSTART, RLENGTH - 1)
                split(tok, parts, "@")
                printf "%s@%.0f\n", parts[1], parts[2]
                exit
            }
        ' || true
}

# set_mode <WxH@R> - switch DP-1 to a mode; return non-zero on failure.
set_mode() {
    [ -n "$1" ] || return 1
    kscreen-doctor output."$OUTPUT".mode."$1" && return 0
    log "failed to set $OUTPUT mode to $1"
    return 1
}

activate() {
    local dir file prior app
    dir=$(state_dir)
    file="$dir/state"
    mkdir -p "$dir"
    chown_to_user "$dir"

    if [ -f "$file" ]; then
        log "already active; keeping recorded state"
    else
        prior=$(current_mode)
        if [ -z "$prior" ]; then
            prior="$MODE_IDLE"
            log "could not read current $OUTPUT mode; recording fallback $prior"
        fi
        printf 'refresh=%s\n' "$prior" > "$file"
        chown_to_user "$file"
    fi

    for app in "${APPS[@]}"; do
        is_running "$app" || continue
        grep -qxF "app=$app" "$file" || printf 'app=%s\n' "$app" >> "$file"
        log "stopping $app"
        stop_app "$app"
    done
    chown_to_user "$file"

    # After the stops: a modeset under a running Chromium kills its GPU process.
    set_mode "$MODE_GAME" || true
}

deactivate() {
    local dir file mode app line
    dir=$(state_dir)
    file="$dir/state"
    if [ ! -f "$file" ]; then
        log "not active (no recorded state); nothing to restore"
        return 0
    fi

    mode=""
    while IFS= read -r line; do
        case "$line" in
            refresh=*) mode="${line#refresh=}" ;;
        esac
    done < "$file"

    if [ -n "$mode" ] && set_mode "$mode"; then
        log "restored $OUTPUT mode $mode"
    else
        log "could not restore mode '${mode:-unset}'; using fallback $MODE_IDLE"
        set_mode "$MODE_IDLE" || true
    fi

    while IFS= read -r line; do
        case "$line" in
            app=*) app="${line#app=}" ;;
            *) continue ;;
        esac
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
