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

    set -l tab (printf '\t')
    set -l span (math "$limit * 1.5")

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

    # grep -I treats NUL-containing files as binary and skips them, so this
    # picks up any text file without an extension whitelist.
    fd -t f --search-path "$base" -0 | xargs -0 -r grep -lIZ '' | xargs -0 -r wc -l | awk -v roots="$root_list" -v project="$project" -v base="$base" -v limit="$limit" '
        BEGIN { n = split(roots, R, "\t"); off = (base == "/" ? 1 : length(base) + 1) }
        {
            count = $1
            $1 = ""
            sub(/^ +/, "")
            path = $0
            if (path == "total") next
            if (count <= limit) next
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
            print best "\t" count "\t" path
        }' | sort -t "$tab" -k1,1 -k2,2nr | awk -F "$tab" -v limit="$limit" -v span="$span" '
    function paint(c,   t, g) {
        t = (c - limit) / span
        if (t < 0) t = 0
        if (t > 1) t = 1
        g = int(255 * (1 - t))
        return esc "[38;2;255;" g ";" g "m" c esc "[0m"
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
        printf "%s\t%s\n", paint($2), $3
    }'
end
