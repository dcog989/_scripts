#!/bin/bash
#
# install-apps.sh - Install apps via pacman (CachyOS v3 / Arch repos)
# and AUR packages via yay or paru.
#
# Usage:  install-apps.sh
#
set -euo pipefail

# Priority 1: CachyOS v3 Optimized & Arch Repos
# Using 'pacman' to ensure repo priority defined in /etc/pacman.conf
REPO_APPS=(
    "bun"
    "claude-code"
    "dbeaver"
    "ghostty"
    "hunspell-en_GB"
    "hunspell-en_US"
    "opencode"
    "rumdl"
    "stacer"
)

# Priority 2: AUR (Packages not in CachyOS or Arch repos)
AUR_APPS=(
    "lefthook"
    "ryzen_smu-dkms-git"
)

# Both halves are the job: refuse to start rather than install half of it.
AUR_HELPER=""
for helper in yay paru; do
    if command -v "$helper" >/dev/null 2>&1; then
        AUR_HELPER="$helper"
        break
    fi
done

if [[ -z "$AUR_HELPER" ]]; then
    echo "No AUR helper found (yay or paru) - install one first" >&2
    exit 1
fi

echo "Installing Repo apps (CachyOS v3 / Arch)..."
sudo pacman -S --needed --noconfirm "${REPO_APPS[@]}"

echo "Installing AUR apps via $AUR_HELPER..."
"$AUR_HELPER" -S --needed --noconfirm "${AUR_APPS[@]}"

echo "Installation complete."
