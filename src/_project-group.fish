# Shared by big-files and long-files: group paths by their enclosing .git
# project and render them largest-first with the same colour ramp.

# __project_group <size|lines> <limit> <roots-soh> <project> <base>
# Reads "value path" lines; prints "group SOH value SOH path".
function __project_group --argument-names mode limit roots project base
    awk -v mode="$mode" -v limit="$limit" -v roots="$roots" -v project="$project" -v base="$base" '
    BEGIN { n = split(roots, R, "\001"); off = (base == "/" ? 1 : length(base) + 1) }
    {
        value = $1
        path = $0
        # strip only the value prefix: rebuilding $0 from fields collapses
        # runs of spaces inside the path
        sub(/^[ \t]*[0-9]+[ \t]+/, "", path)
        if (mode == "lines") {
            if (path == "total") next
            if (value <= limit) next
        } else {
            value = value / 1048576
        }
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
        print best "\001" value "\001" path
    }'
end

# __project_show <size|lines> <limit> <span>
# Reads "group SOH value SOH path" lines; prints the grouped, coloured report.
function __project_show --argument-names mode limit span
    awk -F'\001' -v mode="$mode" -v limit="$limit" -v span="$span" '
    function paint(c,   t, g, txt) {
        t = (c - limit) / span
        if (t < 0) t = 0
        if (t > 1) t = 1
        g = int(255 * (1 - t))
        if (mode == "size") txt = sprintf("%9.1f MiB", c)
        else txt = c
        return esc "[38;2;255;" g ";" g "m" txt esc "[0m"
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
        if (mode == "size") printf "%s  %s\n", paint($2), $3
        else printf "%s\t%s\n", paint($2), $3
    }'
end
