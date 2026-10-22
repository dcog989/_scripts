# List directories whose newest descendant is older than N days, so dormant
# content can be found and removed. A directory is reported only when none of
# its content has been touched since the cutoff; the reported date is that of
# its newest descendant.
#
# Usage:
#   stale [dir] [days]
#
# `dir` defaults to the current directory and `days` to 90. A numeric argument
# is taken as the age limit; any other argument as the base.
function stale --description 'List content not touched for N days'
    set -l base .
    set -l days 90
    for arg in $argv
        if string match -qr '^[0-9]+$' -- $arg
            set days $arg
        else
            set base $arg
        end
    end
    # Normalized so the awk walk can compare it as a literal path prefix.
    set base (path normalize -- $base)

    set -l now (date +%s)
    set -l cutoff (math $now - $days \* 86400)
    # Age ramp: 6 months is the first red shade, 5 years and beyond the deepest.
    set -l ramp_start 180
    set -l ramp_end 1825
    printf 'Content not touched for %s days...\n' $days

    find $base -xdev -maxdepth 4 \
        \( -name .git -o -name .cache -o -name .bun -o -name node_modules -o -name target -o -name .venv \) -prune -o \
        -printf '%y\t%p\t%T@\n' |
        awk -F'\t' -v cutoff="$cutoff" -v now="$now" -v root="$base" \
            -v ramp_start="$ramp_start" -v ramp_end="$ramp_end" '
        function shade(age, line,   t, g) {
            t = (age - ramp_start) / (ramp_end - ramp_start)
            if (t < 0) return line
            if (t > 1) t = 1
            g = int(200 * (1 - t))
            return esc "[38;2;255;" g ";" g "m" line esc "[0m"
        }
        BEGIN { esc = sprintf("%c", 27) }
        $1 == "d" { if ($3 > m[$2]) m[$2] = $3 }
        {
            t = $3
            d = $2
            while (d != root && d != "" && d != "/") {
                sub("/[^/]*$", "", d)
                if (t > m[d]) m[d] = t
            }
        }
        END {
            for (d in m) {
                if (m[d] >= cutoff) continue
                parent = d
                sub("/[^/]*$", "", parent)
                if (parent in m && m[parent] < cutoff) continue
                hits[++n] = d
                age = int((now - m[d]) / 86400)
                if (length(age) > width) width = length(age)
            }
            for (i = 1; i <= n; i++) {
                d = hits[i]
                age = int((now - m[d]) / 86400)
                printf "%s\t%s\n", shade(age, sprintf("%s   %*d days", strftime("%Y-%m-%d", m[d]), width, age)), d
            }
        }' | sort -t "$(printf '\t')" -k2
end
