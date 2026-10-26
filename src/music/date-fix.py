#!/usr/bin/env python3
"""Normalize date tags across a music library to a four-digit year.

Date tags hold mixed forms: "2018", "2018 2018", "2018-05-04", "04/05/2018".
Players then show the whole string. This rewrites every date tag to its year
("2018"), taking the first year when a field holds more than one, and dropping
month, day and duplicate values. Audio is untouched. A field with no
four-digit year is skipped and reported.

Dry run by default; --fix writes the tags.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from mutagen import File
from mutagen.id3 import ID3

DEFAULT_SOURCE = Path("/mnt/data/Music")
AUDIO_EXTENSIONS = {".mp3", ".flac", ".ogg", ".opus", ".m4a"}
DATE_KEYS = {
    "tdrc", "tyer", "tdor", "tdrl",
    "date", "year", "originaldate", "originalyear", "origyear",
    "releasedate", "release date", "©day",
}
YEAR = re.compile(r"(?<!\d)\d{4}(?!\d)")


def first_year(values: list[str]) -> str | None:
    """The first four-digit year across the field's values, or None with no year."""
    for value in values:
        match = YEAR.search(value)
        if match:
            return match.group()
    return None


def is_date_key(key: str) -> bool:
    return key.lower() in DATE_KEYS


def scan(path: Path) -> tuple[list[tuple[str, list[str], list[str]]], list[tuple[str, list[str]]], str | None]:
    """Return (changes, skipped, error). A change is (key, before, after)."""
    try:
        audio = File(path)
        if audio is None or audio.tags is None:
            return [], [], None
        changes = []
        skipped = []
        for key in audio.tags.keys():
            if not is_date_key(key):
                continue
            frame = audio.tags[key]
            before = [str(v) for v in getattr(frame, "text", frame if isinstance(frame, list) else [frame])]
            year = first_year(before)
            if year is None:
                skipped.append((key, before))
            elif [year] != before:
                changes.append((key, before, [year]))
        return changes, skipped, None
    except Exception as exc:  # a broken or unreadable tag must not stop the scan
        return [], [], f"{path}: {exc}"


def apply(path: Path, changes: list[tuple[str, list[str], list[str]]]) -> None:
    audio = File(path)
    if audio is None or audio.tags is None:
        raise RuntimeError("tag disappeared between scan and write")
    for key, _, after in changes:
        frame = audio.tags[key]
        if isinstance(audio.tags, ID3):
            frame.text = after
        else:
            audio.tags[key] = after
    if isinstance(audio.tags, ID3):
        minor = audio.tags.version[1]
        audio.tags.save(path, v2_version=minor if minor in (3, 4) else 4)
    else:
        audio.save()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--fix", action="store_true", help="rewrite the bad tags (default: report only)")
    parser.add_argument("--jobs", type=int, default=8)
    args = parser.parse_args()

    paths = [
        Path(dirpath, name)
        for dirpath, _, names in os.walk(args.source)
        for name in names
        if os.path.splitext(name)[1].lower() in AUDIO_EXTENSIONS
    ]

    paths.sort(key=lambda p: (p.parent, p.name))

    album: Path | None = None
    tracks = 0
    pending: set[tuple[str, str]] = set()
    album_count = 0
    total_tracks = 0
    fields = 0
    fixed = 0
    errors: list[str] = []

    def flush() -> None:
        nonlocal tracks, pending, album_count, total_tracks, fields
        if album is not None:
            if tracks:
                print(f"{album}: {tracks} track(s)", flush=True)
                album_count += 1
                total_tracks += tracks
            for key, value in sorted(pending):
                print(f"{album}: {key} left as it is, no four-digit year: {value!r}", file=sys.stderr, flush=True)
            fields += len(pending)
        tracks = 0
        pending = set()

    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        results = pool.map(scan, paths)
        for path, (changes, bad, error) in zip(paths, results):
            if album != path.parent:
                flush()
                album = path.parent
            if error:
                errors.append(error)
                continue
            for key, rejected in bad:
                pending.add((key, " ".join(rejected)))
            if changes:
                tracks += 1
                if args.fix:
                    try:
                        apply(path, changes)
                        fixed += 1
                    except Exception as exc:
                        errors.append(f"{path}: {exc}")
    flush()

    if args.fix:
        print(f"\n{album_count} album(s), {total_tracks} track(s) to normalize, {fixed} fixed, {fields} field(s) skipped, {len(errors)} error(s)")
    else:
        print(f"\n{album_count} album(s), {total_tracks} track(s) to normalize, {fields} field(s) skipped, {len(errors)} error(s), nothing written")
    for error in errors:
        print(f"error: {error}", file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
