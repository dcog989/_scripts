# List (dry run) then clean pacman and AUR package leftovers: orphans, synced
# package cache, stale download dirs and the AUR build cache.
#
# Usage:
#   repository-clean
#
# The report previews what cleanup would reclaim: cached versions beyond the
# keep-3 prune, cached versions of uninstalled packages, stale download dirs and
# the AUR build cache. It ends with a one-line verdict; with nothing to reclaim
# it says so and returns without prompting. Otherwise it prompts once before
# making any changes and ends with a summary of what was actually removed.
#
function __rc_count --description 'colour a count: green when nonzero, dim when zero'
    set -l n $argv[1]
    test -n "$n"; or set n 0
    if test "$n" -gt 0
        echo (set_color green)$n(set_color normal)
    else
        echo (set_color brblack)$n(set_color normal)
    end
end

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

    set -l paccache
    command -q paccache; and set paccache paccache

    echo
    echo $sec"================ Package maintenance ================"$off

    echo
    echo $sec"Orphans"$off$dim" (pacman -Qdtq)"$off
    set -l orphans (pacman -Qdtq 2>/dev/null)
    if test -z "$orphans"
        echo "  "$ok"none"$off
    else
        echo "  "$bad(count $orphans)" found"$off
        pacman -Qdt | while read -l name ver
            echo "    "$bad$name$off" "$dim$ver$off
        end
    end

    echo
    echo $sec"Package cache"$off$dim" (/var/cache/pacman/pkg)"$off
    echo "  "$dim"total size:     "$off(du -sh /var/cache/pacman/pkg 2>/dev/null | cut -f1)
    # Parse paccache's own dry run so the preview says whether a prune would
    # reclaim anything, instead of echoing its raw output.
    set -l n_old 0
    set -l n_gone 0
    set -l free_old
    set -l free_gone
    if test -n "$paccache"
        set -l out (paccache -d -k $keep 2>/dev/null | tail -1)
        set n_old (string match -r --groups-only '(\d+) candidates' -- $out | head -1)
        set free_old (string match -r --groups-only 'saved: ([^)]+)' -- $out | head -1)
        set -l out (paccache -d -u -k 0 2>/dev/null | tail -1)
        set n_gone (string match -r --groups-only '(\d+) candidates' -- $out | head -1)
        set free_gone (string match -r --groups-only 'saved: ([^)]+)' -- $out | head -1)
        # An empty list disappears from a concatenated echo argument, so default
        # every parsed value to something printable.
        test -z "$n_old"; and set n_old 0
        test -z "$free_old"; and set free_old ''
        test -z "$n_gone"; and set n_gone 0
        test -z "$free_gone"; and set free_gone ''
        echo "  "$dim"superseded:     "$off(__rc_count $n_old)" "$dim$free_old$off
        echo "  "$dim"uninstalled:    "$off(__rc_count $n_gone)" "$dim$free_gone$off
    else
        echo "  "$bad"paccache not installed - cache prune skipped"$off
    end
    set -l n_dl (find /var/cache/pacman/pkg -maxdepth 1 -type d -name 'download-*' 2>/dev/null | count)
    echo "  "$dim"stale downloads: "$off(__rc_count $n_dl)

    set -l aur_mb 0
    if test -n "$aur"
        echo
        echo $sec"AUR build cache"$off$dim" (~/.cache/$aur)"$off
        echo "  "$dim"total size: "$off(du -sh ~/.cache/$aur 2>/dev/null | cut -f1)
        set aur_mb (du -sm ~/.cache/$aur 2>/dev/null | cut -f1)
        test -z "$aur_mb"; and set aur_mb 0
    end

    set -l todo
    test -n "$orphans"; and set -a todo (count $orphans)" orphaned package(s)"
    test $n_old -gt 0; and set -a todo "$n_old superseded package version(s)"
    test $n_gone -gt 0; and set -a todo "$n_gone cached package(s) no longer installed"
    test $n_dl -gt 0; and set -a todo "$n_dl stale download dir(s)"
    test $aur_mb -gt 0; and set -a todo "$aur_mb MiB AUR build cache"

    echo
    if test -z "$todo"
        echo $ok"Nothing to clean."$off
        return 0
    end
    echo $sec"Cleanup will remove: "$off(string join ', ' -- $todo)

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
        if sudo pacman -Rs --noconfirm $orphans
            set n_orphans (count $orphans)
            echo "  "$ok"removed $n_orphans orphaned package(s)"$off
        else
            echo "  "$bad"removal failed - see the pacman output above"$off
        end
    else
        echo "  "$dim"none"$off
    end

    if test -n "$paccache"
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
            printf '%s\n' $res | string match -i '*error*' | while read -l l
                echo "    "$bad$l$off
            end
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
            printf '%s\n' $res | string match -i '*error*' | while read -l l
                echo "    "$bad$l$off
            end
        end
    else
        echo $dim"Skipping cache prune: paccache not installed"$off
    end

    # libalpm downloads into <cache>/download-XXXXXX and leaks that dir when a
    # download is interrupted; `pacman -Sc` then fails reading it as a package.
    echo $sec"== Removing stale pacman download dirs =="$off
    # Only when pacman is idle: download-* dirs are the live download target.
    if pgrep -x pacman >/dev/null
        echo "  "$bad"skipped: pacman is running"$off
    else
        set -l dl (sudo find /var/cache/pacman/pkg -maxdepth 1 -type d -name 'download-*' 2>/dev/null)
        if test (count $dl) -gt 0
            set dldirs_mb (sudo du -sm $dl 2>/dev/null | awk '{s+=$1} END {print s+0}')
            # Re-check right before removing: pacman may have started mid-scan.
            if pgrep -x pacman >/dev/null
                echo "  "$bad"skipped: pacman started during scan"$off
                set dldirs_mb 0
            else
                sudo rm -rf $dl
                set n_dldirs (count $dl)
                echo "  "$ok"removed $n_dldirs stale download dir(s) ($dldirs_mb MiB)"$off
            end
        else
            echo "  "$dim"none"$off
        end
    end

    if test -n "$aur"
        # A build owns part of this cache and may still need its deps: leave both alone.
        set -l aur_busy 0
        for tool in yay paru makepkg
            pgrep -x $tool >/dev/null; and set aur_busy 1
        end
        if test $aur_busy = 1
            echo $sec"== AUR cleanup =="$off
            echo "  "$bad"skipped: a yay/paru/makepkg build is running"$off
        else
            echo $sec"== Cleaning AUR build cache (~/.cache/$aur) =="$off
            # Delete directly, not via `$aur -Sc`: that also runs `pacman -Sc`,
            # which keeps only the latest cached version and undoes the keep-3 prune.
            set -l aur_files_before (count (find ~/.cache/$aur -type f 2>/dev/null))
            if test $aur_files_before -eq 0
                echo "  "$dim"nothing to clean"$off
            else if find ~/.cache/$aur -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null
                set n_aur_files (math $aur_files_before - (count (find ~/.cache/$aur -type f 2>/dev/null)))
            else
                echo "  "$bad"cache clean failed"$off
            end

            echo $sec"== Removing unneeded deps =="$off
            set -l before (count (pacman -Qdtq 2>/dev/null))
            set -l deps_ok 0
            switch $aur
                case yay
                    yay -Yc --noconfirm; and set deps_ok 1
                case paru
                    paru -c --noconfirm; and set deps_ok 1
            end
            set n_aur_deps (math $before - (count (pacman -Qdtq 2>/dev/null)))
            if test $deps_ok = 0
                echo "  "$bad"dep removal failed - see the output above"$off
            else if test $n_aur_deps -gt 0
                echo "  "$ok"removed $n_aur_deps unneeded dep(s)"$off
            else
                echo "  "$dim"nothing to remove"$off
            end
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
    echo "  "$dim"orphaned packages removed:   "$off(__rc_count $n_orphans)
    echo "  "$dim"cache versions pruned:       "$off(__rc_count $n_pruned)
    echo "  "$dim"uninstalled pkgs dropped:    "$off(__rc_count $n_uninstalled)
    echo "  "$dim"stale download dirs removed: "$off(__rc_count $n_dldirs)" ("$dim$dldirs_mb" MiB"$off")"
    echo "  "$dim"AUR build files removed:     "$off(__rc_count $n_aur_files)
    echo "  "$dim"unneeded AUR deps removed:   "$off(__rc_count $n_aur_deps)
    echo "  "$dim"space reclaimed:             "$off(__rc_count $freed_cache)" MiB pacman cache, "$dim(math $aur_before - $aur_after)" MiB AUR cache"$off

    echo $ok'Done.'$off
end
