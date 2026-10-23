# Safe git maintenance for every repo under a directory tree.
#
# It never touches the working tree, uses no `git clean`, never expires reflogs
# (reflogExpire/reflogExpireUnreachable are pinned to never), and never deletes
# branches, tags, stashes or remotes. Only `-a` passes `--prune=now`.
#
# Files that are both tracked and ignored (a tracked file listed in .gitignore is
# usually a mistake) are always reported, but only untracked when -u is passed.
# Removal uses `git rm --cached`, which keeps the file on disk and only stops
# tracking it; changes are staged, not committed. Submodule gitlinks are never
# touched.
#
# Usage:
#   git-maintenance                 # optimize all repos under ~/Projects
#   git-maintenance /some/dir       # optimize repos under a specific directory
#   git-maintenance -b /some/dir    # same, via flag
#   git-maintenance -u              # also untrack reported tracked+ignored files
#   git-maintenance -n              # dry run: report stats, change nothing
#   git-maintenance --dry-run       # same as -n
#   git-maintenance -n -e           # dry run plus the reclaim estimate (slow)
#   git-maintenance -a              # aggressive: adds --aggressive --prune=now
#                                   # (much slower; drops the recovery grace period)
#
# Each repo reports: size before -> after (reclaimed), loose -> packed object
# counts, stale remote refs pruned, and the fsck result. The summary totals
# repos optimized/skipped, space reclaimed and remote refs pruned, then lists
# every tracked+ignored file (as repo/path) and any repo with fsck errors. A dry
# run reports current sizes only and counts repos scanned; -e adds the projected
# reclaim, computed by compressing every object read-only, which costs about as
# much as a real repack.

function __gm_human --description 'format a KiB value as human-readable'
    set -l kb $argv[1]
    test -n "$kb"; or set kb 0
    set -l magnitude (math "abs($kb)")
    if test $magnitude -ge 1048576
        echo (math -s1 "$kb / 1048576")" GiB"
    else if test $magnitude -ge 1024
        echo (math -s1 "$kb / 1024")" MiB"
    else
        echo "$kb KiB"
    end
end

function git-maintenance --description 'Safely optimize all git repos under a directory'
    argparse n/dry-run u/untrack 'b/base=' a/aggressive e/estimate -- $argv; or return 2

    set -l base $HOME/Projects
    test -n "$_flag_base"; and set base "$_flag_base"
    test (count $argv) -gt 0; and set base "$argv[1]"
    set -l dry_run $_flag_dry_run
    set -l aggressive $_flag_aggressive
    set -l untrack $_flag_untrack
    set -l estimate $_flag_estimate

    if not test -d "$base"
        echo "git-maintenance: not a directory: $base" >&2
        return 1
    end

    set -l green (set_color green)
    set -l gold (set_color yellow)
    set -l red (set_color red)
    set -l dim (set_color 8a8a8a)
    set -l off (set_color normal)

    if test -n "$aggressive"
        echo "$red!$off aggressive mode: adding --aggressive --prune=now (much slower, no recovery grace)$off"
    end

    # `git gc` runs `git reflog expire --all` at git's default ages (90/30 days);
    # pin both to never so old recovery points stay reachable, as promised.
    set -l keep_reflog -c gc.reflogExpire=never -c gc.reflogExpireUnreachable=never
    set -l gc_flags --quiet
    if test -n "$aggressive"
        set -a gc_flags --aggressive --prune=now
    else if git gc -h 2>&1 | string match -q '*--cruft*'
        set -a gc_flags --cruft
    end
    set -l has_midx false
    if git repack -h 2>&1 | string match -q '*--write-midx*'
        set has_midx true
    end

    set -l total 0
    set -l optimized 0
    set -l skipped 0
    set -l reclaimed_kb 0
    set -l reclaimable_kb 0
    set -l flagged_repos
    set -l flagged_files
    set -l fsck_error_repos
    set -l pruned_total 0
    set -l seen

    for gitdir in (find "$base" -name .git -prune -print 2>/dev/null | sort)
        set -l repo (dirname "$gitdir")
        set -l name (string replace "$base/" '' "$repo")

        # Resolve the shared object store so linked worktrees/submodules run once.
        set -l common_raw (git -C "$repo" rev-parse --git-common-dir 2>/dev/null)
        set -l common
        if test -n "$common_raw"
            if string match -q '/*' -- "$common_raw"
                set common (realpath "$common_raw")
            else
                set common (realpath "$repo/$common_raw")
            end
        end
        if test -z "$common"
            echo "$red x$off $name $dim(unreadable repo)$off"
            set skipped (math $skipped + 1)
            continue
        end
        if contains -- "$common" $seen
            continue
        end
        set -a seen "$common"
        set total (math $total + 1)

        # Skip repos with an in-progress operation or a live/stale lock.
        set -l gitdir_raw (git -C "$repo" rev-parse --git-dir 2>/dev/null)
        set -l gitdir_abs
        if string match -q '/*' -- "$gitdir_raw"
            set gitdir_abs (realpath "$gitdir_raw")
        else
            set gitdir_abs (realpath "$repo/$gitdir_raw")
        end
        set -l busy
        for marker in index.lock MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD BISECT_LOG rebase-merge rebase-apply
            test -e "$gitdir_abs/$marker"; and set busy "$marker"; and break
        end
        if test -n "$busy"
            echo "$gold !$off $name $gold(skip: $busy present)$off"
            set skipped (math $skipped + 1)
            continue
        end

        # Tracked files matched by the ignore rules, excluding submodule gitlinks.
        # -s gives mode+path in one call, so gitlinks are filtered without a git
        # process per file.
        set -l ignored_files
        for entry in (git -C "$repo" ls-files -s -z -ci --exclude-standard | string split0)
            string match -qr '^160000 ' -- $entry; and continue
            set -a ignored_files (string replace -r '^[0-9]+ [0-9a-f]+ [0-9]+\t' '' -- $entry)
        end
        if test (count $ignored_files) -gt 0
            set -a flagged_repos "$name"
            if test -n "$untrack"; and test -z "$dry_run"
                git -C "$repo" rm --cached --quiet -- $ignored_files
            end
            echo "$gold !$off $name $gold(tracked+ignored:"(count $ignored_files)" file(s))$off"
            for f in $ignored_files
                set -a flagged_files "$name/$f"
                echo "$dim        $f$off"
            end
        end

        # Stats before any mutation.
        set -l raw (git -C "$repo" count-objects -v 2>/dev/null)
        set -l loose (string match -r '^count: [0-9]+' -- $raw | string replace -r '^count: ' '')
        set -l packs (string match -r '^packs: [0-9]+' -- $raw | string replace -r '^packs: ' '')
        set -l loose_kb (string match -r '^size: [0-9]+' -- $raw | string replace -r '^size: ' '')
        test -n "$loose_kb"; or set loose_kb 0
        # Size the shared object store: a linked worktree's own git dir is nearly empty.
        set -l before_kb (du -sk "$common" 2>/dev/null | cut -f1)
        test -n "$before_kb"; or set before_kb 0
        set -l remotes (git -C "$repo" remote)

        if test -n "$dry_run"
            set -l est_part
            if test -n "$estimate"
                # Reclaim estimate = current object storage (loose + packs) minus the
                # pack git would rebuild (read-only). Existing cruft packs are kept by
                # gc, so add their bytes back.
                set -l packdir (git -C "$repo" rev-parse --path-format=absolute --git-path objects/pack 2>/dev/null)
                set -l cur_b 0
                set -l cruft_b 0
                for pf in "$packdir"/*.pack
                    test -e "$pf"; or continue
                    set -l psz (stat -c%s "$pf" 2>/dev/null)
                    test -n "$psz"; or set psz 0
                    set cur_b (math "$cur_b + $psz")
                    set -l mt (string replace -r '\.pack$' '.mtimes' "$pf")
                    test -e "$mt"; and set cruft_b (math "$cruft_b + $psz")
                end
                set -l newb (git -C "$repo" pack-objects --all --reflog --indexed-objects --stdout 2>/dev/null | wc -c)
                test -n "$newb"; or set newb 0
                set -l est_b (math "$loose_kb * 1024 + $cur_b - $newb - $cruft_b")
                test "$est_b" -lt 0; and set est_b 0
                set -l est_kb (math "floor($est_b / 1024)")
                set reclaimable_kb (math "$reclaimable_kb + $est_kb")
                set est_part "  est.reclaim: "(__gm_human $est_kb)
            end
            echo "$dim    $name$est_part  loose:$loose/"(__gm_human $loose_kb)" packs:$packs remotes:"(count $remotes)" .git:"(__gm_human $before_kb)$off
            set optimized (math $optimized + 1)
            continue
        end

        # Optimize (working tree is never touched).
        set -l pruned 0
        for remote in $remotes
            set -l pout (env GIT_TERMINAL_PROMPT=0 git -C "$repo" remote prune "$remote" 2>&1)
            set pruned (math $pruned + (count (string match -r '\[pruned\]' -- $pout)))
        end
        set pruned_total (math $pruned_total + $pruned)
        git -C "$repo" worktree prune >/dev/null 2>&1
        git -C "$repo" $keep_reflog gc $gc_flags
        git -C "$repo" commit-graph write --reachable >/dev/null 2>&1
        if test "$has_midx" = true
            git -C "$repo" repack --write-midx=incremental --quiet >/dev/null 2>&1
        end
        set -l fsck_out (git -C "$repo" fsck --full --no-progress 2>&1)
        set -l dangling (count (string match -r 'dangling ' -- $fsck_out))
        set -l fsck_state
        if test (count (string match -r 'error:|fatal:|missing' -- $fsck_out)) -gt 0
            set fsck_state "$red fsck:ERRORS$off"
            set -a fsck_error_repos "$name"
        else if test $dangling -gt 0
            set fsck_state "fsck:ok ($dangling dangling)"
        else
            set fsck_state "fsck:ok"
        end

        # Stats after.
        set -l raw2 (git -C "$repo" count-objects -v 2>/dev/null)
        set -l loose2 (string match -r '^count: [0-9]+' -- $raw2 | string replace -r '^count: ' '')
        set -l packs2 (string match -r '^packs: [0-9]+' -- $raw2 | string replace -r '^packs: ' '')
        set -l after_kb (du -sk "$common" 2>/dev/null | cut -f1)
        test -n "$after_kb"; or set after_kb 0

        set -l delta (math "$before_kb - $after_kb")
        set reclaimed_kb (math "$reclaimed_kb + $delta")

        echo "$green >$off $name  "(__gm_human $before_kb)" -> "(__gm_human $after_kb)"  ("(__gm_human $delta)")  loose:$loose->$loose2 packs:$packs->$packs2  pruned:$pruned  $fsck_state"

        set optimized (math $optimized + 1)
    end

    set -l tail "reclaimed: "(__gm_human $reclaimed_kb)
    set -l counted optimized
    if test -n "$dry_run"
        set counted scanned
        set tail "dry run: nothing changed"
        test -n "$estimate"; and set tail "reclaimable (est.): "(__gm_human $reclaimable_kb)
    end
    echo
    echo $green"$counted: "$off$optimized"   "$gold"skipped: "$off$skipped"   "$dim"discovered: "$off$total"   "$tail
    test $pruned_total -gt 0; and echo $dim"remote refs pruned: "$off$pruned_total

    set -l untrack_state "left tracked; pass -u to untrack"
    test -n "$untrack"; and set untrack_state "staged for untracking; commit each repo to apply"
    test -n "$dry_run"; and set untrack_state "dry run: left tracked"
    if test (count $flagged_files) -gt 0
        echo $gold"tracked+ignored: "(count $flagged_files)" file(s) in "(count $flagged_repos)" repo(s) "$dim"($untrack_state)"$off
        for f in $flagged_files
            echo $dim"    "$f$off
        end
    else
        echo $dim"tracked+ignored: none"$off
    end

    if test (count $fsck_error_repos) -gt 0
        echo $red"fsck errors: "(count $fsck_error_repos)" repo(s)"$off
        for r in $fsck_error_repos
            echo $dim"    "$r$off
        end
    end
end
