import argparse
import sys
from pathlib import Path

from dicmerge import __version__
from dicmerge.config import DEFAULT_CONFIG_PATH
from dicmerge.core import list_sources, run
from dicmerge.exceptions import ConfigError, DicmergeError

_SHOW_CONFIG = object()


def main() -> None:
    parser = argparse.ArgumentParser(
        prog="dicmerge",
        description="Scan, merge, and write back custom user dictionaries",
    )
    parser.add_argument(
        "--write-back",
        action="store_true",
        help="Write new words back to source files",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview only, no files written",
    )
    parser.add_argument(
        "--version",
        action="version",
        version=f"dicmerge {__version__}",
        help="Show version",
    )
    parser.add_argument(
        "--list-sources",
        action="store_true",
        help="Show discovered source files",
    )
    parser.add_argument(
        "--config",
        nargs="?",
        type=Path,
        const=_SHOW_CONFIG,
        default=None,
        metavar="CONFIG",
        help="Set path to config file",
    )

    args = parser.parse_args()

    if args.config is _SHOW_CONFIG:
        print(f"Config path: {DEFAULT_CONFIG_PATH}")
        return

    try:
        if args.config is not None and not args.config.is_file():
            raise ConfigError(f"Config file not found: {args.config}")

        if args.list_sources:
            _print_sources(list_sources(args.config))
            return
        if args.dry_run:
            print("Dry run mode — no files will be written")
        result = run(
            config_path=args.config,
            write_back=args.write_back,
            dry_run=args.dry_run,
        )
    except DicmergeError as e:
        print(f"Error: {e}")
        sys.exit(e.exit_code)

    print("\nScanning:")
    for name, count in sorted(result["source_stats"].items()):
        if count:
            print(f"  ✓ {name}: {count} words")
        else:
            print(f"  ⚠ {name}: not found")

    print(
        f"\nTotal unique words: {result['total_unique']} "
        f"(from {result['total_raw']} raw, {result['total_filtered']} after filters)"
    )
    output_label = "Output would be written to" if args.dry_run else "Output"
    print(f"{output_label}: {result['output_path']}")

    if result["write_back_stats"]:
        heading = "Write-back (dry run — no files written):" if args.dry_run else "Write-back:"
        print(f"\n{heading}")
        for name, entries in sorted(result["write_back_stats"].items()):
            for filename, count in entries:
                print(f"  ✓ {name}: {filename} → {count} words")

    print("\nDone.")


def _print_sources(discovered: dict[str, list[Path]]) -> None:
    print("Discovered Sources")
    for name, files in sorted(discovered.items()):
        if files:
            print(f"  {name}:")
            for f in files:
                print(f"    {f}")
        else:
            print(f"  {name}: none found")
