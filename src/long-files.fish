# Report text files exceeding 400 lines, grouped by their enclosing project
# and sorted by line count descending (largest first). A directory is treated as
# a project root when it contains a `.git` marker; files outside any project are
# grouped by their top-level directory. When `base` is itself a project, all
# results are reported under that project.
#
# Usage:
#   long-files [base] [lines]
#
# `base` defaults to the current directory and `lines` to 400. A numeric
# argument is taken as the line limit; any other argument as the base.
source (path dirname (path resolve (status filename)))/_project-group.fish

function long-files --description 'Recurse project directory for over-sized files'
    set -l base .
    # Files above this many lines are reported; it also anchors the colour ramp.
    set -l limit 400
    for arg in $argv
        if string match -qr '^[0-9]+$' -- $arg
            set limit $arg
        else
            set base $arg
        end
    end
    # Normalized so the awk group can strip it as a literal prefix (fd echoes
    # --search-path verbatim).
    set base (path normalize -- $base)

    # SOH as the internal field separator: paths may contain tabs.
    set -l sep (printf '\001')
    set -l span (math "max($limit * 1.5, 1)")

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

    # PDFs and lock files are excluded by extension; grep -I skips other binary
    # files, so there is still no extension whitelist.
    fd -t f -E '*.[pP][dD][fF]' -E '*.[lL][oO][cC][kK]' --search-path "$base" -0 | xargs -0 -r grep -lIZ '' | xargs -0 -r wc -l | __project_group lines "$limit" "$root_list" "$project" "$base" | sort -t "$sep" -k1,1 -k2,2nr | __project_show lines "$limit" "$span"
end
