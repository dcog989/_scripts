# Report (and optionally fix) files that are both tracked and ignored.
#
# A tracked file listed in .gitignore is usually a mistake: ignore rules have no
# effect on tracked files. Removal uses `git rm --cached`, which keeps the file
# on disk and only stops tracking it. Submodule gitlinks are never touched.
# Changes are staged, not committed.
#
# Usage:
#   git-ignore-tidy                 # scan all repos under /home/bubba/Projects
#   git-ignore-tidy /some/dir       # scan a specific directory
#   git-ignore-tidy -b /some/dir    # same, via flag
#   git-ignore-tidy -n              # report only, never prompt or remove
#   git-ignore-tidy -y              # untrack all matches without prompting

function git-ignore-tidy --description 'Untrack files that are both tracked and ignored'
    argparse 'n/dry-run' 'y/yes' 'b/base=' -- $argv; or return 2

    set -l base /home/bubba/Projects
    test -n "$_flag_base"; and set base "$_flag_base"
    test (count $argv) -gt 0; and set base "$argv[1]"
    set -l dry_run $_flag_dry_run
    set -l assume_yes $_flag_yes

    if not test -d "$base"
        echo "git-ignore-tidy: not a directory: $base" >&2
        return 1
    end

    set -l green (set_color green)
    set -l gold (set_color yellow)
    set -l red (set_color red)
    set -l dim (set_color 8a8a8a)
    set -l off (set_color normal)

    set -l repos 0
    set -l flagged 0
    set -l removed 0
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
            continue
        end
        if contains -- "$common" $seen
            continue
        end
        set -a seen "$common"
        set repos (math $repos + 1)

        # Skip repos with an in-progress operation.
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
            continue
        end

        # Tracked files matched by the ignore rules, excluding submodule gitlinks.
        set -l files
        for f in (git -C "$repo" ls-files -z -ci --exclude-standard | string split0)
            set -l entry (git -C "$repo" ls-files -s -z -- "$f" | string split0)
            set -l mode (string match -r '^[0-9]+' -- $entry)
            test "$mode" = 160000; and continue
            set -a files "$f"
        end

        if test (count $files) -eq 0
            continue
        end

        set flagged (math $flagged + (count $files))
        echo "$green>$off $name  $gold"(count $files)" tracked+ignored file(s)$off"
        for f in $files
            echo "$dim    $f$off"
        end

        if test -n "$dry_run"
            continue
        end

        set -l do_remove false
        if test -n "$assume_yes"
            set do_remove true
        else
            read -l ans -P "  Untrack these (keeps files on disk)? [y/N] "
            string match -qi 'y*' -- $ans; and set do_remove true
        end

        if test "$do_remove" = true
            git -C "$repo" rm --cached --quiet -- $files
            echo "  $green untracked "(count $files)" file(s)$off"
            set removed (math $removed + (count $files))
        end
    end

    if test $removed -gt 0; and test -z "$dry_run"
        echo
        echo "$gold Changes are staged; commit each repo to apply.$off"
    end

    echo
    echo $green"repos: "$off$repos"   "$gold"flagged files: "$off$flagged"   "$green"untracked: "$off$removed
end
