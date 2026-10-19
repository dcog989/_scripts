#!/usr/bin/env bash
# Replace each destination file with the source file at the same relative path.
# Compares the two trees by path only. Default is a dry run that reports exactly
# what --apply would do; --apply does it.
set -euo pipefail

source_tree=/mnt/data/Music-48k
destination_tree=/mnt/data/Music

apply=0
case "${1:-}" in
    --apply) apply=1 ;;
    "") ;;
    *) printf 'usage: %s [--apply]\n' "${0##*/}" >&2; exit 2 ;;
esac

for tree in "$source_tree" "$destination_tree"; do
    [ -d "$tree" ] || { printf 'no such tree: %s\n' "$tree" >&2; exit 1; }
done

source_list() { cd "$source_tree" && find . -type f -printf '%P\n' | sort; }
destination_list() { cd "$destination_tree" && find . -type f -printf '%P\n' | sort; }
names_in() { (cd "$1" 2>/dev/null && find . -maxdepth 1 -type f -printf '%f\n' | sort) || true; }
count() { printf '%s\n' "$1" | grep -c . || true; }

total_source=$(source_list | wc -l)
total_destination=$(destination_list | wc -l)

replaced=0
skipped=0
while IFS= read -r relative; do
    target="$destination_tree/$relative"
    if [ ! -f "$target" ]; then
        skipped=$((skipped + 1))
        continue
    fi
    if [ "$apply" = 1 ]; then
        mv -f -- "$source_tree/$relative" "$target"
        printf 'replaced %s\n' "$relative"
    else
        printf 'would replace %s\n' "$relative"
    fi
    replaced=$((replaced + 1))
done < <(source_list)

while IFS= read -r dir; do
    source_names=$(names_in "$source_tree/$dir")
    destination_names=$(names_in "$destination_tree/$dir")
    only_source=$(comm -23 <(printf '%s\n' "$source_names") <(printf '%s\n' "$destination_names") | grep . || true)
    only_destination=$(comm -13 <(printf '%s\n' "$source_names") <(printf '%s\n' "$destination_names") | grep . || true)
    [ -z "$only_source$only_destination" ] && continue
    printf '\n%s/  %s in source, %s in destination\n' \
        "$dir" "$(count "$source_names")" "$(count "$destination_names")" >&2
    [ -n "$only_source" ] &&
        printf '%s\n' "$only_source" | sed 's/^/  only in source:      /' >&2
    [ -n "$only_destination" ] &&
        printf '%s\n' "$only_destination" | sed 's/^/  only in destination: /' >&2
    true
done < <(cd "$source_tree" && find . -mindepth 1 -type d -printf '%P\n' | sort)

unpaired_destination=$(comm -13 <(source_list) <(destination_list) | wc -l)

if [ "$apply" = 1 ]; then
    printf '\n%s of %s source files replaced, %s skipped with no destination file\n' \
        "$replaced" "$total_source" "$skipped"
else
    printf '\n%s of %s source files would replace their destination file, %s skipped with no destination file\n' \
        "$replaced" "$total_source" "$skipped"
    printf 'dry run: nothing changed. Re-run with --apply to move.\n'
fi
printf '%s of %s destination files have no source file: left untouched\n' \
    "$unpaired_destination" "$total_destination"
