# Update the opencode CLI and desktop AppImage from the latest GitHub release.
# Installs the CLI to ~/.local/bin/opencode and the AppImage to
# ~/.local/bin/opencode-desktop.AppImage. Both assets are downloaded before the
# running desktop instance is stopped, so a failed download leaves it running.
#
# Usage:
#   opencode-update
#
# No-op only when the CLI, the AppImage and its recorded version all match the
# latest release tag.
function opencode-update --description 'Update opencode CLI and desktop AppImage'
    set -l rel (curl -sfL https://api.github.com/repos/anomalyco/opencode/releases/latest)
    if test $status -ne 0
        echo "FAIL: could not fetch the latest release"
        return 1
    end
    set -l ver (echo $rel | jq -r .tag_name | string trim --chars=v)
    if test -z "$ver"; or test "$ver" = null
        echo "FAIL: no release tag in the API response"
        return 1
    end

    set -l appimage ~/.local/bin/opencode-desktop.AppImage
    set -l stamp ~/.local/state/opencode/desktop.version

    # Current only when the CLI, the AppImage and its recorded version all match;
    # the AppImage version is recorded here because it cannot be queried without
    # launching the desktop GUI.
    set -l current (opencode --version 2>/dev/null)
    set -l installed
    test -f "$stamp"; and set installed (string trim < "$stamp")
    if test "$current" = "$ver"; and test -f "$appimage"; and test "$installed" = "$ver"
        echo "opencode is already up to date ($ver)"
        return 0
    end

    set -l cli_url (echo $rel | jq -r '.assets[] | select(.name=="opencode-linux-x64.tar.gz") | .browser_download_url')
    set -l desk_url (echo $rel | jq -r '.assets[] | select(.name=="opencode-desktop-linux-x86_64.AppImage") | .browser_download_url')
    if test -z "$cli_url"; or test "$cli_url" = null; or test -z "$desk_url"; or test "$desk_url" = null
        echo "FAIL: release $ver is missing an asset"
        return 1
    end

    echo "updating opencode $current -> $ver"
    set -l tmp (mktemp -d)

    # Download and unpack both assets before touching the running install.
    if not curl -sfL -o $tmp/oc.tar.gz "$cli_url"
        echo "FAIL: cli download"
        rm -rf $tmp
        return 1
    end
    if not tar -xzf $tmp/oc.tar.gz -C $tmp
        echo "FAIL: extract"
        rm -rf $tmp
        return 1
    end
    if not curl -sfL -o $tmp/desk.AppImage "$desk_url"
        echo "FAIL: desktop download"
        rm -rf $tmp
        return 1
    end

    # Both assets are on disk; only now stop the running opencode processes.
    pkill -TERM -f "ai.opencode.desktop" 2>/dev/null
    sleep 2
    pkill -KILL -f "ai.opencode.desktop" 2>/dev/null
    pkill -KILL -f ".mount_.*opencode" 2>/dev/null

    if not mv -f $tmp/opencode ~/.local/bin/opencode
        echo "FAIL: cli install"
        rm -rf $tmp
        return 1
    end
    if not mv -f $tmp/desk.AppImage $appimage
        echo "FAIL: desktop install"
        rm -rf $tmp
        return 1
    end
    chmod +x $appimage
    mkdir -p (dirname "$stamp")
    echo $ver > "$stamp"

    rm -rf $tmp
    echo "opencode updated to $ver"
end
