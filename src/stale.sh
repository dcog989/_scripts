#!/bin/sh
# stale.sh [root] [days] - list directories whose newest descendant is older than N days
root=${1:-$HOME}
days=${2:-90}
max_depth=4
[ "$root" = / ] || root=${root%/}
cutoff=$(( $(date +%s) - days * 86400 ))
printf 'Content not touched for %s days...\n' "$days"

find "$root" -xdev -maxdepth "$max_depth" \
    \( -name .git -o -name .cache -o -name .bun -o -name node_modules -o -name target -o -name .venv \) -prune -o \
    -printf '%y\t%p\t%T@\n' |
awk -F'\t' -v cutoff="$cutoff" -v root="$root" '
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
        printf "%s\t%s\n", strftime("%Y-%m-%d", m[d]), d
    }
}' | sort -t "$(printf '\t')" -k2
