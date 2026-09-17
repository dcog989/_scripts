# Report source files exceeding 400 lines, grouped by their enclosing project
# and sorted by line count descending (largest first). A directory is treated as
# a project root when it contains a `.git` marker; files outside any project are
# grouped by their top-level directory. When `base` is itself a project, all
# results are reported under that project.
#
# Usage:
#   big-files [base]
#
# `base` defaults to the current directory.
function big-files --description 'Recurse project directory for over-sized files'
    set -l base .
    if test (count $argv) -gt 0
        set base $argv[1]
    end

    set -l tab (printf '\t')

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

    fd -t f -e js -e ts -e jsx -e tsx -e svelte -e slint -e rs -e py -e c -e cpp -e h -e hpp -e go -e rb -e php -e css -e scss -e html -e sql -e sh -e fish --search-path "$base" -x wc -l | awk -v roots="$root_list" -v project="$project" '
        BEGIN { n = split(roots, R, "\t") }
        {
            count = $1
            $1 = ""
            sub(/^ +/, "")
            path = $0
            if (count <= 400) next
            if (project != "") {
                best = project
            } else {
                best = ""
                for (i = 1; i <= n; i++) {
                    if (index(path, R[i] "/") == 1 && length(R[i]) > length(best)) {
                        best = R[i]
                    }
                }
                if (best == "") {
                    split(path, parts, "/")
                    best = (parts[3] == "" ? "." : parts[2])
                }
                sub(/^\.\//, "", best)
            }
            print best "\t" count "\t" path
        }' | sort -t "$tab" -k1,1 -k2,2nr | awk -F "$tab" '
    function paint(c,   t, g) {
        t = (c - 400) / 600
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
