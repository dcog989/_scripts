# Update the opencode CLI and desktop AppImage from the latest GitHub release.
# Installs the CLI to ~/.local/bin/opencode and the AppImage to
# ~/.local/bin/opencode-desktop.AppImage, terminating any running desktop
# instance first.
#
# Usage:
#   opencode-update
#
# No-op when the installed CLI already matches the latest release tag.
function opencode-update --description 'Update opencode CLI and desktop AppImage'
    set -l rel (curl -s https://api.github.com/repos/anomalyco/opencode/releases/latest)
    set -l ver (echo $rel | jq -r .tag_name | string trim --chars=v)

    set -l current (opencode --version 2>/dev/null)
    if test "$current" = "$ver"
        echo "opencode is already up to date ($ver)"
        return 0
    end
    echo "updating opencode $current -> $ver"
    set -l tmp (mktemp -d)

    # Stop any running opencode processes
    pkill -TERM -f "ai.opencode.desktop" 2>/dev/null
    sleep 2
    pkill -KILL -f "ai.opencode.desktop" 2>/dev/null
    pkill -KILL -f ".mount_.*opencode" 2>/dev/null

    # CLI
    if not curl -sfL -o $tmp/oc.tar.gz (echo $rel | jq -r '.assets[] | select(.name=="opencode-linux-x64.tar.gz") | .browser_download_url')
        echo "FAIL: cli download"
        return 1
    end
    if not tar -xzf $tmp/oc.tar.gz -C $tmp
        echo "FAIL: extract"
        return 1
    end
    if not mv -f $tmp/opencode ~/.local/bin/opencode
        echo "FAIL: cli install"
        return 1
    end

    # Desktop
    if not curl -sfL -o $tmp/desk.AppImage (echo $rel | jq -r '.assets[] | select(.name=="opencode-desktop-linux-x86_64.AppImage") | .browser_download_url')
        echo "FAIL: desktop download"
        return 1
    end
    if not mv -f $tmp/desk.AppImage ~/.local/bin/opencode-desktop.AppImage
        echo "FAIL: desktop install"
        return 1
    end
    chmod +x ~/.local/bin/opencode-desktop.AppImage

    rm -rf $tmp
    echo "opencode updated to $ver"
end
