#!/usr/bin/env python3
"""Cap a FLAC library at 16-bit / 48 kHz, keeping the rate family.

Anything above 48 kHz is downsampled (44.1 family to 44.1 kHz, 48 family to
48 kHz) and anything above 16 bit is reduced to 16 bit with dither. Files
carrying a non-standard ID3v2 tag in front of the FLAC stream are rewritten
without it, whatever their rate and depth. Sources are never modified: output
goes to a separate target tree. Tags and cover art are carried over explicitly,
not left to the encoder.

Modes:
    scan     report the library's rate/bit-depth mix, write the job list
    convert  transcode the job list into the target tree
    verify   check every output against its source
"""

from __future__ import annotations

import argparse
import collections
import os
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from pathlib import Path

DESCRIPTION = "Cap a FLAC library at 16-bit / 48 kHz, keeping the rate family"
DEFAULT_SOURCE = Path("/mnt/data/Music")
DEFAULT_TARGET = Path("/mnt/data/Music-48k")
DEFAULT_JOB_LIST = Path("/tmp/opencode/flac-conversion-jobs.tsv")

RATE_CAP = 48000
BITS_CAP = 16
RATE_FAMILY = 44100
SOXR_PRECISION = 28
DITHER_METHOD = "triangular_hp"
FLAC_COMPRESSION = 8
DEFAULT_JOBS = 4
PROGRESS_INTERVAL = 500
STREAMINFO_SIZE = 42
HEAD_BYTES = 64
ID3V2_HEADER_SIZE = 10
CONTAINER_MAGIC = (
    (b"OggS", "Ogg container (Vorbis, Opus or FLAC-in-Ogg)"),
    (b"RIFF", "RIFF container (WAV)"),
    (b"MAC ", "Monkey's Audio"),
    (b"\x1aE\xdf\xa3", "Matroska or WebM"),
    (b"APETAGEX", "APE tag"),
    (b"\x00\x00\x00\x00", "all-zero header (truncated or sparse file)"),
)
MODE_TOOLS = {
    "scan": (),
    "convert": ("ffmpeg", "ffprobe", "metaflac"),
    "verify": ("flac", "ffprobe", "metaflac"),
}
FFPROBE_TAG_ENTRY = "format_tags"
FFPROBE_TAG_PREFIX = "TAG:"


@dataclass(frozen=True)
class StreamInfo:
    rate: int
    bits: int
    channels: int


@dataclass(frozen=True)
class Entry:
    source: Path
    relative: Path
    current: StreamInfo
    rate: int
    bits: int


def read_head(path: Path, size: int) -> bytes:
    with path.open("rb") as handle:
        return handle.read(size)


def read_streaminfo(path: Path) -> StreamInfo:
    """Read rate/bit depth/channels from a FLAC STREAMINFO header block."""
    head = read_head(path, HEAD_BYTES)
    offset = id3v2_length(head)
    if offset:
        # non-standard, but real libraries contain FLAC with an ID3v2 tag in front
        head = read_head(path, offset + STREAMINFO_SIZE)[offset:]
    # shortcut: assumes STREAMINFO is the first metadata block, which the FLAC spec requires
    if len(head) < STREAMINFO_SIZE or head[:4] != b"fLaC":
        raise ValueError("not a FLAC stream")
    packed = head[18:26]
    rate = (packed[0] << 12) | (packed[1] << 4) | (packed[2] >> 4)
    channels = ((packed[2] >> 1) & 0x07) + 1
    bits = (((packed[2] & 0x01) << 4) | (packed[3] >> 4)) + 1
    return StreamInfo(rate, bits, channels)


def id3v2_length(head: bytes) -> int:
    """Total length of a leading ID3v2 tag, or 0 when there is none."""
    if len(head) < ID3V2_HEADER_SIZE or not head.startswith(b"ID3"):
        return 0
    size = 0
    for byte in head[6:10]:
        size = (size << 7) | (byte & 0x7F)
    footer = ID3V2_HEADER_SIZE if head[5] & 0x10 else 0
    return ID3V2_HEADER_SIZE + size + footer


def describe_file(path: Path) -> str:
    """Identify why a file could not be read, from its leading bytes."""
    try:
        head = read_head(path, HEAD_BYTES)
    except OSError as error:
        return str(error)
    if not head:
        return "empty file"
    tag_length = id3v2_length(head)
    if tag_length:
        after = read_head(path, tag_length + 4)[tag_length:]
        if after == b"fLaC":
            return f"FLAC with a {tag_length}-byte ID3v2 tag prepended"
        return f"ID3v2 tag with no FLAC header after it ({tag_length} bytes)"
    if head.startswith(b"fLaC"):
        return f"truncated FLAC (only {len(head)} bytes, STREAMINFO needs {STREAMINFO_SIZE})"
    for magic, name in CONTAINER_MAGIC:
        if head.startswith(magic):
            return name
    if head[4:8] == b"ftyp":
        return "MP4 container (AAC or ALAC)"
    if head[:1] == b"\xff" and head[1] & 0xE0 == 0xE0:
        return "MPEG audio"
    printable = all(32 <= byte < 127 for byte in head[:4])
    return (
        f"{head[:4]!r} text-ish header"
        if printable
        else f"unrecognised header {head[:4]!r}"
    )


def normalise_tags(tags: list[tuple[str, str]]) -> set[str]:
    """Compare tags case-insensitively by key, but not by value."""
    return {f"{key.lower()}={value}" for key, value in tags}


def read_metadata(path: Path) -> tuple[int, set[str]]:
    """Count PICTURE blocks and collect VORBIS_COMMENT tags in one pass."""
    # metaflac exits 1 when a file has neither block, which is a normal result here
    result = subprocess.run(
        [
            "metaflac",
            "--no-utf8-convert",
            "--list",
            "--block-type=PICTURE",
            "--block-type=VORBIS_COMMENT",
            str(path),
        ],
        capture_output=True,
        check=False,
        encoding="utf-8",
    )
    output = result.stdout or ""
    pictures = output.count("type: 6 (PICTURE)")
    tags: list[tuple[str, str]] = []
    for line in output.splitlines():
        if line.strip().startswith("comment["):
            key, _, value = line.split(": ", 1)[1].partition("=")
            tags.append((key, value))
    return pictures, normalise_tags(tags)


def probe_tags(path: Path) -> list[tuple[str, str]]:
    """Tags as ffprobe sees them, which includes a non-standard ID3v2 tag."""
    result = subprocess.run(
        [
            "ffprobe",
            "-v",
            "error",
            "-show_entries",
            FFPROBE_TAG_ENTRY,
            "-of",
            "default=noprint_wrappers=1",
            str(path),
        ],
        capture_output=True,
        check=False,
        encoding="utf-8",
    )
    tags: list[tuple[str, str]] = []
    for line in (result.stdout or "").splitlines():
        if not line.startswith(FFPROBE_TAG_PREFIX):
            continue
        key, _, value = line[len(FFPROBE_TAG_PREFIX) :].partition("=")
        if key:
            tags.append((key, value))
    return tags


def copy_tags(source: Path, target: Path) -> None:
    """Write the source's tags into the output as Vorbis comments.

    ffmpeg's own metadata handling is bypassed on purpose: the ffprobe view
    includes an ID3v2 tag, so tags survive even where ffmpeg would drop them.
    """
    tags = probe_tags(source)
    subprocess.run(
        ["metaflac", "--remove-all-tags", str(target)],
        check=True,
        capture_output=True,
        encoding="utf-8",
    )
    if not tags:
        return
    payload = "".join(f"{key}={value}\n" for key, value in tags)
    subprocess.run(
        ["metaflac", "--no-utf8-convert", "--import-tags-from=-", str(target)],
        input=payload,
        encoding="utf-8",
        check=True,
        capture_output=True,
    )


def needs_conversion(info: StreamInfo, tag_length: int) -> bool:
    return info.rate > RATE_CAP or info.bits > BITS_CAP or tag_length > 0


def target_format(info: StreamInfo) -> tuple[int, int]:
    rate = info.rate
    if rate > RATE_CAP:
        rate = RATE_FAMILY if rate % RATE_FAMILY == 0 else RATE_CAP
    return rate, min(info.bits, BITS_CAP)


def report_progress(done: int, total: int, label: str) -> None:
    if done != total and done % PROGRESS_INTERVAL:
        return
    percent = 100 * done // total if total else 100
    end = "\n" if done == total else "\r"
    print(f"{label} {done}/{total} ({percent}%)", end=end, file=sys.stderr, flush=True)


def scan(
    source: Path,
) -> tuple[
    list[Entry],
    list[tuple[Path, str]],
    collections.Counter[tuple[int, int]],
    list[tuple[Path, int]],
]:
    entries: list[Entry] = []
    problems: list[tuple[Path, str]] = []
    mix: collections.Counter[tuple[int, int]] = collections.Counter()
    tagged: list[tuple[Path, int]] = []

    files = [
        path
        for path in sorted(source.rglob("*"))
        if path.is_file() and path.suffix.lower() == ".flac"
    ]
    for done, path in enumerate(files, start=1):
        report_progress(done, len(files), "scanning")
        try:
            tag_length = id3v2_length(read_head(path, ID3V2_HEADER_SIZE))
            if tag_length:
                tagged.append((path, tag_length))
            info = read_streaminfo(path)
        except (OSError, ValueError) as error:
            problems.append((path, str(error)))
            continue
        mix[(info.rate, info.bits)] += 1
        if needs_conversion(info, tag_length):
            rate, bits = target_format(info)
            entries.append(Entry(path, path.relative_to(source), info, rate, bits))

    return entries, problems, mix, tagged


def write_job_list(path: Path, entries: list[Entry]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        f"{e.source}\t{e.relative}\t{e.current.rate}\t{e.current.bits}"
        f"\t{e.current.channels}\t{e.rate}\t{e.bits}"
        for e in entries
    ]
    path.write_text("\n".join(lines) + ("\n" if lines else ""))


def read_job_list(path: Path) -> list[Entry]:
    entries: list[Entry] = []
    for line in path.read_text().splitlines():
        source, relative, rate, bits, channels, out_rate, out_bits = line.split("\t")
        entries.append(
            Entry(
                Path(source),
                Path(relative),
                StreamInfo(int(rate), int(bits), int(channels)),
                int(out_rate),
                int(out_bits),
            )
        )
    return entries


def build_command(entry: Entry, temporary: Path) -> list[str]:
    stages: list[str] = []
    if entry.rate != entry.current.rate:
        stages.append(
            f"aresample=resampler=soxr:precision={SOXR_PRECISION}:osr={entry.rate}"
        )
    if entry.bits < entry.current.bits:
        # second stage: no rate change, so this only converts format, with dither
        stages.append(f"aresample=osf=s16:dither_method={DITHER_METHOD}")
    # fmt: off
    command = [
        "ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
        "-i", str(entry.source),
        "-map", "0",
    ]
    if stages:
        command += ["-af", ",".join(stages)]
    command += [
        "-c:a", "flac", "-compression_level", str(FLAC_COMPRESSION),
        "-c:v", "copy",
        "-f", "flac", str(temporary),
    ]
    return command
    # fmt: on


def is_converted(target: Path, entry: Entry) -> bool:
    if not target.exists():
        return False
    try:
        info = read_streaminfo(target)
    except (OSError, ValueError):
        return False
    return info.rate == entry.rate and info.bits == entry.bits


def convert_one(entry: Entry, target_root: Path, dry_run: bool) -> str:
    target = target_root / entry.relative
    if is_converted(target, entry):
        return "skipped"
    if dry_run:
        print(" ".join(build_command(entry, target)))
        print(f"then: copy tags from {entry.source} to {target}")
        return "planned"
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_name(target.name + ".part")
    try:
        subprocess.run(build_command(entry, temporary), check=True)
        copy_tags(entry.source, temporary)
        os.replace(temporary, target)
    except (subprocess.CalledProcessError, OSError) as error:
        temporary.unlink(missing_ok=True)
        raise RuntimeError(f"failed: {entry.source} ({error})") from error
    return "converted"


def convert(
    entries: list[Entry], target_root: Path, jobs: int, dry_run: bool
) -> tuple[collections.Counter[str], list[str]]:
    counts: collections.Counter[str] = collections.Counter()
    failures: list[str] = []
    total = len(entries)

    def run(pair: tuple[int, Entry]) -> tuple[Entry, str, str | None]:
        _, entry = pair
        try:
            return entry, convert_one(entry, target_root, dry_run), None
        except RuntimeError as error:
            return entry, "failed", str(error)

    with ThreadPoolExecutor(max_workers=jobs) as pool:
        results = pool.map(run, enumerate(entries, start=1))
        for index, (entry, status, error) in enumerate(results, start=1):
            counts[status] += 1
            if status == "failed":
                failures.append(error or str(entry.relative))
                print(f"[{index}/{total}] FAILED {entry.relative}", file=sys.stderr)
            elif status == "converted":
                print(f"[{index}/{total}] {entry.relative}")

    return counts, failures


def summarise(counts: collections.Counter[str], total: int) -> str:
    return (
        f"{counts['converted']} converted, {counts['skipped']} already done, "
        f"{counts['planned']} planned, {counts['failed']} failed of {total}"
    )


def decode_failure(path: Path) -> str | None:
    """Run the reference decoder over the whole file; None when it is clean."""
    result = subprocess.run(
        ["flac", "-t", "-s", str(path)],
        capture_output=True,
        encoding="utf-8",
    )
    if result.returncode == 0:
        return None
    lines = [
        line.strip()
        for line in ((result.stderr or "") + (result.stdout or "")).splitlines()
        if line.strip()
    ]
    return lines[0] if lines else "decoder exited non-zero"


def verify(entries: list[Entry], target_root: Path) -> list[str]:
    problems: list[str] = []
    for done, entry in enumerate(entries, start=1):
        report_progress(done, len(entries), "verifying")
        target = target_root / entry.relative
        if not target.exists():
            problems.append(f"missing output: {target}")
            continue
        # a file that does not decode has no meaningful format or tags to compare
        if failure := decode_failure(target):
            problems.append(f"does not decode: {target}: {failure}")
            continue
        try:
            info = read_streaminfo(target)
        except (OSError, ValueError) as error:
            problems.append(f"unreadable output: {target}: {error}")
            continue
        if (info.rate, info.bits, info.channels) != (
            entry.rate,
            entry.bits,
            entry.current.channels,
        ):
            problems.append(
                f"wrong format: {target} is {info.rate} Hz/{info.bits} bit/{info.channels} ch, "
                f"expected {entry.rate} Hz/{entry.bits} bit/{entry.current.channels} ch"
            )
        source_pictures, _ = read_metadata(entry.source)
        target_pictures, target_tags = read_metadata(target)
        source_tags = normalise_tags(probe_tags(entry.source))
        if source_pictures != target_pictures:
            problems.append(
                f"cover art count changed: {target} has {target_pictures}, "
                f"source has {source_pictures}"
            )
        if source_tags - target_tags:
            problems.append(
                f"tags missing: {target} lacks {sorted(source_tags - target_tags)}"
            )
    return problems


def plural(count: int, noun: str) -> str:
    return f"{count} {noun}" if count == 1 else f"{count} {noun}s"


def report_problems(problems: list[tuple[Path, str]], source: Path) -> None:
    if not problems:
        return
    groups: collections.Counter[tuple[str, str]] = collections.Counter()
    for path, _ in problems:
        groups[(str(path.parent.relative_to(source)), describe_file(path))] += 1
    folders = len({path.parent for path, _ in problems})
    print(
        f"\ncould not read {plural(len(problems), 'file')} in {folders} folders:",
        file=sys.stderr,
    )
    for (folder, reason), count in sorted(
        groups.items(), key=lambda item: (-item[1], item[0][0])
    ):
        print(f"  {plural(count, 'file'):>9}  {folder}  -- {reason}", file=sys.stderr)


def report_tagged(tagged: list[tuple[Path, int]], source: Path) -> None:
    """Group ID3v2-tagged files by folder so each affected album is visible."""
    if not tagged:
        return
    by_folder: dict[str, list[int]] = collections.defaultdict(list)
    for path, tag_length in tagged:
        by_folder[str(path.parent.relative_to(source))].append(tag_length)
    print(
        f"\n{plural(len(tagged), 'file')} with a non-standard ID3v2 tag in front of the"
        " FLAC stream (rewritten to drop the tag, tags and cover art carried over):",
        file=sys.stderr,
    )
    for folder in sorted(by_folder, key=lambda key: (-len(by_folder[key]), key)):
        lengths = sorted(set(by_folder[folder]))
        span = f"{lengths[0]}" if len(lengths) == 1 else f"{lengths[0]}-{lengths[-1]}"
        print(
            f"  {plural(len(by_folder[folder]), 'file'):>9}  {folder}"
            f"  -- ID3v2 tag of {span} bytes",
            file=sys.stderr,
        )


def report_mix(mix: collections.Counter[tuple[int, int]]) -> None:
    if not mix:
        return
    print(f"{'rate':>8} {'bits':>4} {'files':>7}")
    for (rate, bits), count in sorted(
        mix.items(), key=lambda item: (-item[0][0], -item[0][1])
    ):
        print(f"{rate:>8} {bits:>4} {count:>7}")


def resolve_target(source: Path, target: Path) -> Path:
    source = source.resolve()
    target = target.resolve()
    if target == source or source in target.parents:
        raise ValueError(f"target {target} is inside source {source}")
    return target


def require_tools(mode: str) -> None:
    missing = [tool for tool in MODE_TOOLS[mode] if not shutil.which(tool)]
    if missing:
        raise RuntimeError(f"missing required tools: {', '.join(missing)}")


def build_parser() -> argparse.ArgumentParser:
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    common.add_argument("--target", type=Path, default=DEFAULT_TARGET)
    common.add_argument("--job-list", type=Path, default=DEFAULT_JOB_LIST)

    parser = argparse.ArgumentParser(description=DESCRIPTION)
    modes = parser.add_subparsers(dest="mode", required=True)
    modes.add_parser(
        "scan",
        parents=[common],
        help="report the rate/bit-depth mix and write the job list",
    )
    convert_parser = modes.add_parser(
        "convert", parents=[common], help="transcode the job list into the target tree"
    )
    convert_parser.add_argument("--jobs", type=int, default=DEFAULT_JOBS)
    convert_parser.add_argument("--dry-run", action="store_true")
    modes.add_parser(
        "verify", parents=[common], help="check every output against its source"
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        require_tools(args.mode)
        target = resolve_target(args.source, args.target)
    except (RuntimeError, ValueError) as error:
        print(error, file=sys.stderr)
        return 1

    if args.mode == "scan":
        entries, problems, mix, tagged = scan(args.source)
        report_mix(mix)
        report_problems(problems, args.source)
        report_tagged(tagged, args.source)
        write_job_list(args.job_list, entries)
        total = sum(mix.values())
        excluded = (
            f" ({plural(len(problems), 'file')} unreadable, excluded)"
            if problems
            else ""
        )
        print(
            f"\n{len(entries)}/{total} readable files need conversion"
            f"{excluded} -> {args.job_list}"
        )
        return 0

    if not args.job_list.exists():
        print(f"no job list at {args.job_list}; run scan first", file=sys.stderr)
        return 1
    entries = read_job_list(args.job_list)

    if args.mode == "convert":
        print(
            f"converting {plural(len(entries), 'file')} -> {target} ({args.jobs} workers)",
            file=sys.stderr,
        )
        counts, failures = convert(entries, target, args.jobs, args.dry_run)
        for failure in failures:
            print(failure, file=sys.stderr)
        print(f"\n{summarise(counts, len(entries))}")
        return 1 if failures else 0

    problems = verify(entries, target)
    for problem in problems:
        print(problem, file=sys.stderr)
    print(f"\n{len(entries) - len(problems)}/{len(entries)} outputs match their source")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
