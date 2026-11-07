import argparse
import sys
from pathlib import Path

from dicmerge import __version__
from dicmerge.config import DEFAULT_CONFIG_PATH
from dicmerge.core import Prepared, list_sources, prepare, write
from dicmerge.exceptions import ConfigError, DicmergeError

_SHOW_CONFIG = object()


def main() -> None:
    parser = argparse.ArgumentParser(
        prog="dicmerge",
        description="Scan, merge, and write back custom user dictionaries",
        suggest_on_error=True,
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
        prepared = prepare(args.config)
    except DicmergeError as e:
        print(f"Error: {e}")
        sys.exit(e.exit_code)

    _print_report(prepared)

    if not _confirm_write():
        print("\nNothing written.")
        return

    try:
        result = write(prepared, write_back=True)
    except DicmergeError as e:
        print(f"Error: {e}")
        sys.exit(e.exit_code)

    print(f"\nWritten: {result['output_path']}")
    if result["write_back_stats"]:
        print("\nWrite-back:")
        for name, entries in sorted(result["write_back_stats"].items()):
            for filename, count in entries:
                print(f"  ✓ {name}: {filename} → {count} new words")
    print("\nDone.")


def _confirm_write() -> bool:
    try:
        answer = input("Write changes? [y/N] ")
    except EOFError:
        print()
        return False
    return answer.strip().casefold() in {"y", "yes"}


def _print_report(prepared: Prepared) -> None:
    print("\nScanning:")
    for name, count in sorted(prepared["source_stats"].items()):
        failed = prepared["failed_stats"].get(name, 0)
        if failed:
            print(f"  ⚠ {name}: {failed} file(s) failed (see log)")
        elif count:
            print(f"  ✓ {name}: {count} words")
        else:
            print(f"  ⚠ {name}: not found")

    for warning in prepared["warnings"]:
        print(f"  ⚠ {warning}")

    print(
        f"\nTotal unique words: {len(prepared['output_words'])} "
        f"(from {prepared['total_raw']} raw, {prepared['total_filtered']} after filters)"
    )
    print(f"Output would be written to: {prepared['output_path']}")

    if prepared["write_back_preview"]:
        print("\nWrite-back (nothing written yet):")
        for name, entries in sorted(prepared["write_back_preview"].items()):
            for filename, count in entries:
                print(f"  ✓ {name}: {filename} → {count} new words")


def _print_sources(discovered: dict[str, list[Path]]) -> None:
    print("Discovered Sources")
    for name, files in sorted(discovered.items()):
        if files:
            print(f"  {name}:")
            for f in files:
                print(f"    {f}")
        else:
            print(f"  {name}: none found")
