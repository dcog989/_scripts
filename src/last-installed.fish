function last-installed --description 'Colourised tail of pacman transactions with version-diff highlighting'
    set -l count 50
    if test (count $argv) -gt 0
        set count $argv[1]
    end
    if not string match -qr '^[1-9][0-9]*$' -- $count
        echo "usage: last-installed [COUNT] (COUNT >= 1)" >&2
        return 2
    end

    set -l log /var/log/pacman.log
    if not test -r $log
        echo "last-installed: cannot read $log" >&2
        return 1
    end

    # Foreign packages (AUR) are those absent from every sync database.
    # shortcut: packages promoted into a repo or dropped from all repos since
    # install are mislabelled; upgrade if pacman ever logs the origin.
    set -l repo_file
    if command -q pacman
        set repo_file (mktemp)
        pacman -Slq 2>/dev/null | sort -u > $repo_file; or set repo_file ""
        test -s "$repo_file"; or set repo_file ""
    end

    awk -v count=$count -v repo_file="$repo_file" '
    BEGIN {
        e = "\033"
        dim = e "[2m"; rst = e "[0m"; bold = e "[1m"; pink = e "[38;5;213m"
        act["upgraded"]    = e "[1;32m"
        act["installed"]   = e "[1;36m"
        act["reinstalled"] = e "[1;35m"
        lvl[1] = e "[1;31m"; name[1] = "major"
        lvl[2] = e "[1;33m"; name[2] = "minor"
        lvl[3] = e "[1;32m"; name[3] = "patch"
        lvl[4] = e "[1;34m"; name[4] = "build"
        if (repo_file != "") {
            while ((getline pkg < repo_file) > 0) repo[pkg] = 1
            close(repo_file)
        }
    }

    function parse(v, p,   s, n, i) {
        split("", p)
        p["epoch"] = ""; p["rel"] = ""
        if (match(v, /:/)) { p["epoch"] = substr(v, 1, RSTART - 1); v = substr(v, RSTART + 1) }
        if (match(v, /-[^-]+$/)) { p["rel"] = substr(v, RSTART + 1); v = substr(v, 1, RSTART - 1) }
        n = split(v, s, ".")
        p["n"] = n
        for (i = 1; i <= n; i++) p[i] = s[i]
    }

    function colorize(oldv, newv,   po, pn, i, out, l) {
        parse(oldv, po); parse(newv, pn)
        tag = ""; tagcol = dim; out = ""
        if (pn["epoch"] != "") {
            if (pn["epoch"] != po["epoch"]) { out = out lvl[1] pn["epoch"] rst; tag = "epoch"; tagcol = lvl[1] }
            else out = out dim pn["epoch"] rst
            out = out dim ":" rst
        }
        for (i = 1; i <= pn["n"]; i++) {
            if (i > 1) out = out dim "." rst
            if (i in po && po[i] == pn[i]) { out = out dim pn[i] rst; continue }
            l = (i > 4 ? 4 : i)
            out = out lvl[l] pn[i] rst
            if (tag == "") { tag = name[l]; tagcol = lvl[l] }
        }
        if (pn["rel"] != "") {
            out = out dim "-" rst
            if (pn["rel"] != po["rel"]) {
                out = out lvl[4] pn["rel"] rst
                if (tag == "") { tag = "pkgrel"; tagcol = lvl[4] }
            } else out = out dim pn["rel"] rst
        }
        return out
    }

    $3 in act {
        tag = ""; tagcol = dim
        v = $0
        sub(/^[^(]*\(/, "", v); sub(/\).*$/, "", v)
        if ($3 == "upgraded") {
            n = split(v, w, " -> ")
            body = dim w[1] rst " " dim "→" rst " " colorize(w[1], w[2])
        } else {
            body = v
        }
        if (tag != "") body = body "  " tagcol "(" tag ")" rst
        if (repo_file != "" && !($4 in repo)) body = body " " pink "*AUR" rst
        buf[cnt % count] = dim substr($1, 2, 10) " " substr($1, 13, 5) rst "  " \
            act[$3] sprintf("%-11s", $3) rst " " bold sprintf("%-24s", $4) rst "  " body
        cnt++
    }

    END {
        start = (cnt > count) ? cnt - count : 0
        for (i = start; i < cnt; i++) print buf[i % count]
    }
    ' $log
    set -l rc $status
    test -n "$repo_file"; and rm -f $repo_file
    return $rc
end
