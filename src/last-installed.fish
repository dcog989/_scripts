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
    # Repos are listed in pacman.conf order, so the first hit is the one pacman
    # would install from (CachyOS v3 rebuilds win over the Arch upstream).
    set -l repo_tmp
    set -l repo_file
    if command -q pacman
        set repo_tmp (mktemp)
        pacman -Sl 2>/dev/null | awk '{print $1, $2}' > $repo_tmp
        test -s "$repo_tmp"; and set repo_file $repo_tmp
    end

    set -l base https://packages.cachyos.org/package/
    awk -v count=$count -v repo_file="$repo_file" -v base="$base" '
    function repo_arch(r) {
        if (r ~ /-v3$/)     return "x86_64_v3"
        if (r ~ /-v4$/)     return "x86_64_v4"
        if (r ~ /-znver4$/) return "x86_64_v4"
        return "x86_64"
    }

    function rgb(r, g, b) { return "\033[38;2;" r ";" g ";" b "m" }

    BEGIN {
        e = "\033"
        bs = sprintf("%c", 92)  # backslash; escapes are mangled by the fish quoting layer
        # Nine hue-distinct truecolor values (~25-70 degrees apart) so no two
        # elements can be confused, independent of the terminal theme.
        dim = e "[2m"; rst = e "[0m"
        white = e "[38;2;255;255;255m"  # new-version digits that did not change
        darkred = e "[38;2;196;115;95m"  # old-version digits that did change; ~4.8:1 on a dark bg
        pink = rgb(240, 101, 149)   # *AUR
        namecol = rgb(77, 171, 247) # package name
        act["upgraded"]    = rgb(81, 207, 102)
        act["installed"]   = rgb(56, 217, 169)
        act["reinstalled"] = rgb(177, 151, 252)
        lvl[1] = rgb(255, 107, 107); name[1] = "major"
        lvl[2] = rgb(255, 146, 43);  name[2] = "minor"
        lvl[3] = rgb(255, 224, 102); name[3] = "patch"
        lvl[4] = rgb(232, 121, 249); name[4] = "build"
        if (repo_file != "") {
            while ((getline line < repo_file) > 0) {
                split(line, f, " ")
                if (f[2] in repo) continue
                repo[f[2]] = 1
                repo_name[f[2]] = f[1]
                repo_arch_of[f[2]] = repo_arch(f[1])
            }
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
            else out = out white pn["epoch"] rst
            out = out white ":" rst
        }
        for (i = 1; i <= pn["n"]; i++) {
            if (i > 1) out = out white "." rst
            if (i in po && po[i] == pn[i]) { out = out white pn[i] rst; continue }
            l = (i > 4 ? 4 : i)
            out = out lvl[l] pn[i] rst
            if (tag == "") { tag = name[l]; tagcol = lvl[l] }
        }
        if (pn["rel"] != "") {
            out = out white "-" rst
            if (pn["rel"] != po["rel"]) {
                out = out lvl[4] pn["rel"] rst
                if (tag == "") { tag = "pkgrel"; tagcol = lvl[4] }
            } else out = out white pn["rel"] rst
        }
        return out
    }

    function colorize_old(oldv, newv,   po, pn, i, out) {
        parse(oldv, po); parse(newv, pn)
        out = ""
        if (po["epoch"] != "") {
            if (po["epoch"] != pn["epoch"]) out = out darkred po["epoch"] rst
            else out = out dim po["epoch"] rst
            out = out dim ":" rst
        }
        for (i = 1; i <= po["n"]; i++) {
            if (i > 1) out = out dim "." rst
            if (i in pn && pn[i] == po[i]) { out = out dim po[i] rst; continue }
            out = out darkred po[i] rst
        }
        if (po["rel"] != "") {
            out = out dim "-" rst
            if (po["rel"] != pn["rel"]) out = out darkred po["rel"] rst
            else out = out dim po["rel"] rst
        }
        return out
    }

    $3 in act {
        tag = ""; tagcol = dim
        v = $0
        sub(/^[^(]*\(/, "", v); sub(/\).*$/, "", v)
        if ($3 == "upgraded") {
            n = split(v, w, " -> ")
            body = colorize_old(w[1], w[2]) " " dim "→" rst " " colorize(w[1], w[2])
        } else {
            body = v
        }
        if (tag != "") body = body "  " tagcol "(" tag ")" rst
        if (repo_file != "" && !($4 in repo)) body = body " " pink "*AUR" rst
        pad = (24 > length($4)) ? sprintf("%" (24 - length($4)) "s", "") : ""
        if ($4 in repo) {
            url = base repo_name[$4] "/" repo_arch_of[$4] "/" $4
            cell = namecol e "]8;;" url e bs $4 e "]8;;" e bs pad rst
        } else cell = namecol $4 pad rst
        buf[cnt % count] = dim substr($1, 2, 10) " " substr($1, 13, 5) rst "  " \
            act[$3] sprintf("%-11s", $3) rst " " cell "  " body
        cnt++
    }

    END {
        start = (cnt > count) ? cnt - count : 0
        for (i = start; i < cnt; i++) print buf[i % count]
    }
    ' $log
    set -l rc $status
    test -n "$repo_tmp"; and rm -f $repo_tmp
    return $rc
end
