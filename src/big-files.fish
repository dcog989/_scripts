# List files larger than a size threshold, grouped by their enclosing project
# and sorted by size descending (largest first). A directory is treated as a
# project root when it contains a `.git` marker; files outside any project are
# grouped by their top-level directory. When `base` is itself a project, all
# results are reported under that project.
#
# Usage:
#   big-files [base] [mb]
#   big-files [-s mb] [base]
#
# `base` defaults to the current directory and the size to 5 (MB). A numeric
# argument is taken as the size limit; any other argument as the base.
source (path dirname (path resolve (status filename)))/_project-group.fish

function big-files --description 'List files larger than a size threshold'
    argparse 's/size=' -- $argv; or return 2

    set -l base .
    set -l size 5
    test -n "$_flag_size"; and set size $_flag_size
    for arg in $argv
        if string match -qr '^[0-9]*\.?[0-9]+$' -- $arg
            set size $arg
        else
            set base $arg
        end
    end
    if not string match -qr '^[0-9]*\.?[0-9]+$' -- $size
        echo "big-files: size must be a positive number of MB" >&2
        return 2
    end
    # Normalized so the awk group can strip it as a literal prefix (fd echoes
    # --search-path verbatim).
    set base (path normalize -- $base)

    # SOH as the internal field separator: paths may contain tabs.
    set -l sep (printf '\001')
    set -l span (math "max($size * 4, 1)")
    set -l bytes (math "round($size * 1048576)")

    set -l project
    if test -e "$base/.git"
        set project (path basename (path resolve "$base"))
    end

    set -l roots
    for root in (fd -H --no-ignore -t d -g '.git' --search-path "$base" 2>/dev/null | path dirname)
        if test "$root" != "$base"
            set -a roots $root
        end
    end
    set -l root_list (string join "$sep" $roots)

    fd -H --no-ignore -t f --size "+$bytes"b --search-path "$base" -0 | xargs -0 -r stat -c '%s %n' | __project_group size "$size" "$root_list" "$project" "$base" | sort -t "$sep" -k1,1 -k2,2nr | __project_show size "$size" "$span"
end
