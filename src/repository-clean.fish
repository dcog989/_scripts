# List (dry run) then clean pacman and AUR package leftovers: orphans, synced
# package cache, stale download dirs and the AUR build cache.
#
# Usage:
#   repository-clean
#
# The package cache report previews what cleanup reclaims: cached versions
# beyond the keep-3 prune, plus every cached version of an uninstalled package.
# Cleanup prompts once before making any changes and ends with a summary of
# what was actually removed.
#
function repository-clean --description 'List then clean pacman/AUR package leftovers'
    set -l sec (set_color --bold yellow)
    set -l ok (set_color green)
    set -l bad (set_color red)
    set -l dim (set_color brblack)
    set -l off (set_color normal)

    # Cached versions kept per installed package: prune step and preview share it.
    set -l keep 3

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
    echo "  "$dim"old versions:  "$off(paccache -d -k $keep 2>/dev/null | tail -1)
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

    # Counters and sizes for the summary.
    set -l n_orphans 0
    set -l n_pruned 0
    set -l n_uninstalled 0
    set -l n_dldirs 0
    set -l n_aur_files 0
    set -l n_aur_deps 0
    set -l dldirs_mb 0

    set -l cache_before (du -sm /var/cache/pacman/pkg 2>/dev/null | cut -f1)
    test -z "$cache_before"; and set cache_before 0
    set -l aur_before 0
    if test -n "$aur"
        set aur_before (du -sm ~/.cache/$aur 2>/dev/null | cut -f1)
        test -z "$aur_before"; and set aur_before 0
    end

    echo
    echo $sec"== Removing orphans =="$off
    if test -n "$orphans"
        sudo pacman -Rns --noconfirm $orphans
        set n_orphans (count $orphans)
        echo "  "$ok"removed $n_orphans orphaned package(s)"$off
    else
        echo "  "$dim"none"$off
    end

    echo $sec"== Pruning cache (keep $keep) =="$off
    set -l res (sudo paccache -r -k $keep 2>&1)
    set -l m (string match -r --groups-only 'finished: (\d+) packages removed' -- $res '' | head -1)
    if test -n "$m"
        set n_pruned $m
        echo "  "$ok"pruned $n_pruned package version(s)"$off
    else
        echo "  "$dim"nothing to clean"$off
    end
    if string match -qi '*error*' -- $res ''
        printf '%s\n' $res | string match -i '*error*'
    end

    echo $sec"== Removing uninstalled from cache =="$off
    set -l res (sudo paccache -r -u -k 0 2>&1)
    set -l m (string match -r --groups-only 'finished: (\d+) packages removed' -- $res '' | head -1)
    if test -n "$m"
        set n_uninstalled $m
        echo "  "$ok"removed $n_uninstalled package(s) of uninstalled software"$off
    else
        echo "  "$dim"nothing to clean"$off
    end
    if string match -qi '*error*' -- $res ''
        printf '%s\n' $res | string match -i '*error*'
    end

    # libalpm downloads into <cache>/download-XXXXXX and leaks that dir when a
    # download is interrupted; `pacman -Sc` then fails reading it as a package.
    echo $sec"== Removing stale pacman download dirs =="$off
    # Never while pacman runs: download-* dirs are the live download target.
    if pgrep -x pacman >/dev/null
        echo "  "$bad"skipped: pacman is running"$off
    else
        set -l dl (sudo find /var/cache/pacman/pkg -maxdepth 1 -type d -name 'download-*' 2>/dev/null)
        if test (count $dl) -gt 0
            set dldirs_mb (sudo du -sm $dl 2>/dev/null | awk '{s+=$1} END {print s+0}')
            sudo rm -rf $dl
            set n_dldirs (count $dl)
            echo "  "$ok"removed $n_dldirs stale download dir(s) ($dldirs_mb MiB)"$off
        else
            echo "  "$dim"none"$off
        end
    end

    if test -n "$aur"
        echo $sec"== Cleaning AUR build cache (~/.cache/$aur) =="$off
        # Delete directly, not via `$aur -Sc`: that also runs `pacman -Sc`,
        # which keeps only the latest cached version and undoes the keep-3 prune.
        set -l aur_files_before (count (find ~/.cache/$aur -type f 2>/dev/null))
        rm -rf ~/.cache/$aur/* 2>/dev/null
        set -l aur_files_after (count (find ~/.cache/$aur -type f 2>/dev/null))
        set n_aur_files (math $aur_files_before - $aur_files_after)

        echo $sec"== Removing unneeded deps =="$off
        set -l before (count (pacman -Qdtq 2>/dev/null))
        switch $aur
            case yay
                yay -Yc --noconfirm
            case paru
                paru -c --noconfirm
        end
        set n_aur_deps (math $before - (count (pacman -Qdtq 2>/dev/null)))
        if test $n_aur_deps -gt 0
            echo "  "$ok"removed $n_aur_deps unneeded dep(s)"$off
        else
            echo "  "$dim"nothing to remove"$off
        end
    else
        echo $dim"No AUR helper (yay/paru) found - skipping AUR cleanup"$off
    end

    set -l cache_after (du -sm /var/cache/pacman/pkg 2>/dev/null | cut -f1)
    test -z "$cache_after"; and set cache_after 0
    set -l aur_after 0
    if test -n "$aur"
        set aur_after (du -sm ~/.cache/$aur 2>/dev/null | cut -f1)
        test -z "$aur_after"; and set aur_after 0
    end
    # du as a normal user cannot read the leaked download dirs, so their size
    # is added from the root-only measurement taken when they were removed.
    set -l freed_cache (math (math $cache_before - $cache_after) + $dldirs_mb)

    echo
    echo $sec"== Summary =="$off
    echo "  "$dim"orphaned packages removed:   "$off$n_orphans
    echo "  "$dim"cache versions pruned:       "$off$n_pruned
    echo "  "$dim"uninstalled pkgs dropped:    "$off$n_uninstalled
    echo "  "$dim"stale download dirs removed: "$off$n_dldirs" ("$dldirs_mb" MiB)"$off
    echo "  "$dim"AUR build files removed:     "$off$n_aur_files
    echo "  "$dim"unneeded AUR deps removed:   "$off$n_aur_deps
    echo "  "$dim"space reclaimed:             "$off$freed_cache" MiB pacman cache, "(math $aur_before - $aur_after)" MiB AUR cache"

    echo $ok'Done.'$off
end
