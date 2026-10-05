# List (dry run) then clean pacman and AUR package leftovers: orphans, synced
# package cache, stale download dirs and the AUR build cache.
#
# Usage:
#   repository-clean
#
# The package cache report previews what the AUR helper's `-Sc` will reclaim
# (old versions at keep-1 plus uninstalled packages), so the counts match the
# space actually freed. Cleanup prompts once before making any changes.
#
function repository-clean --description 'List then clean pacman/AUR package leftovers'
    set -l sec (set_color --bold yellow)
    set -l ok (set_color green)
    set -l bad (set_color red)
    set -l dim (set_color brblack)
    set -l off (set_color normal)

    set -l aur
    command -q yay; and set aur yay
    if not test -n "$aur"
        command -q paru; and set aur paru
    end

    echo
    echo $sec"================ Package maintenance ================"$off

    echo
    echo $sec"Orphans"$off" (pacman -Qdtq)"
    set -l orphans (pacman -Qdtq 2>/dev/null)
    if test -z "$orphans"
        echo "  "$ok"none"$off
    else
        echo "  "$bad(count $orphans)" found"$off
        pacman -Qdt | sed 's/^/    /'
    end

    echo
    echo $sec"Explicitly installed"$off" (pacman -Qe | wc -l)"
    echo "  "$dim"count: "$off(pacman -Qe | wc -l)

    echo
    echo $sec"Package cache"$off" (/var/cache/pacman/pkg)"
    echo "  "$dim"total size:    "$off(du -sh /var/cache/pacman/pkg 2>/dev/null | cut -f1)
    echo "  "$dim"old versions:  "$off(paccache -d -k 1 2>/dev/null | tail -1)
    echo "  "$dim"uninstalled:   "$off(paccache -d -u -k 0 2>/dev/null | tail -1)

    if test -n "$aur"
        echo
        echo $sec"AUR build cache"$off" (~/.cache/$aur)"
        echo "  "$dim"total size: "$off(du -sh ~/.cache/$aur 2>/dev/null | cut -f1)
    end

    echo
    read -l ans -P "Run cleanup? [y/N] "
    if not string match -qi 'y*' -- $ans
        echo 'Aborted.'
        return 1
    end

    echo
    echo $sec"== Removing orphans =="$off
    if test -n "$orphans"
        sudo pacman -Rns --noconfirm $orphans
        echo "  "$ok"removed "(count $orphans)" orphaned package(s)"$off
    else
        echo "  "$dim"none"$off
    end

    echo $sec"== Pruning cache (keep 3) =="$off
    set -l res (sudo paccache -r -k 3 2>&1)
    if string match -q '*no candidate*' -- $res
        echo "  "$dim"nothing to clean"$off
    else
        echo "  "$ok$res$off
    end

    echo $sec"== Removing uninstalled from cache =="$off
    set -l res (sudo paccache -r -u -k 0 2>&1)
    if string match -q '*no candidate*' -- $res
        echo "  "$dim"nothing to clean"$off
    else
        echo "  "$ok$res$off
    end

    if test -n "$aur"
        echo $sec"== Removing stale pacman download dirs =="$off
        sudo find /var/cache/pacman/pkg -maxdepth 1 -type d -name 'download-*' -exec rm -rf {} + 2>/dev/null

        echo $sec"== Cleaning AUR build cache ($aur -Sc) =="$off
        set -l bp (du -sm /var/cache/pacman/pkg 2>/dev/null | cut -f1)
        set -l ba (du -sm ~/.cache/$aur 2>/dev/null | cut -f1)
        $aur -Sc --noconfirm
        set -l ap (du -sm /var/cache/pacman/pkg 2>/dev/null | cut -f1)
        set -l aa (du -sm ~/.cache/$aur 2>/dev/null | cut -f1)
        set -l freed (math (math $bp - $ap) + (math $ba - $aa))
        if test $freed -gt 0
            echo "  "$ok"freed $freed MiB"$off
        else
            echo "  "$dim"nothing to clean"$off
        end

        echo $sec"== Removing unneeded deps =="$off
        set -l before (count (pacman -Qdtq 2>/dev/null))
        switch $aur
            case yay
                yay -Yc --noconfirm
            case paru
                paru -c --noconfirm
        end
        set -l removed (math $before - (count (pacman -Qdtq 2>/dev/null)))
        if test $removed -gt 0
            echo "  "$ok"removed $removed unneeded dep(s)"$off
        else
            echo "  "$dim"nothing to remove"$off
        end
    else
        echo $dim"No AUR helper (yay/paru) found - skipping AUR cleanup"$off
    end

    echo $ok'Done.'$off
end
