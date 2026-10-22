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

    set -l tab (printf '\t')
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
    set -l root_list (string join "$tab" $roots)

    fd -H --no-ignore -t f --size "+$bytes"b --search-path "$base" -x stat -c '%s %n' | awk -v roots="$root_list" -v project="$project" -v base="$base" '
        BEGIN { n = split(roots, R, "\t"); off = (base == "/" ? 1 : length(base) + 1) }
        {
            mib = $1 / 1048576
            $1 = ""
            sub(/^ +/, "")
            path = $0
            if (project != "") {
                best = project
            } else {
                best = ""
                for (i = 1; i <= n; i++) {
                    if (index(path, R[i] "/") == 1 && length(R[i]) > length(best)) {
                        best = R[i]
                    }
                }
                if (best != "") {
                    best = substr(best, off + 1)
                } else {
                    # Group = first path component under base.
                    rel = substr(path, off + 1)
                    if (index(rel, "/") == 0) best = "."
                    else { split(rel, parts, "/"); best = parts[1] }
                }
            }
            print best "\t" mib "\t" path
        }' | sort -t "$tab" -k1,1 -k2,2nr | awk -F "$tab" -v limit="$size" -v span="$span" '
    function paint(c,   t, g) {
        t = (c - limit) / span
        if (t < 0) t = 0
        if (t > 1) t = 1
        g = int(255 * (1 - t))
        return esc "[38;2;255;" g ";" g "m" sprintf("%9.1f MiB", c) esc "[0m"
    }
    BEGIN { esc = sprintf("%c", 27) }
    {
        if ($1 != dir) {
            if (dir != "") {
                printf "\n"
            }
            printf "%s=== %s ===%s\n", esc "[1;36m", $1, esc "[0m"
            dir = $1
        }
        printf "%s  %s\n", paint($2), $3
    }'
end
