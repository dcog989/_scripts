#!/bin/bash
#
# install-apps.sh - Install apps via pacman (CachyOS v3 / Arch repos)
# and AUR packages via yay.
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

echo "Installing Repo apps (CachyOS v3 / Arch)..."
sudo pacman -S --needed --noconfirm "${REPO_APPS[@]}"

echo "Installing AUR apps via yay..."
yay -S --needed --noconfirm "${AUR_APPS[@]}"

echo "Installation complete."
