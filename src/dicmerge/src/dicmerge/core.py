import re
import shutil
from pathlib import Path
from typing import Any

from dicmerge.config import load_config
from dicmerge.dedup import deduplicate
from dicmerge.exceptions import NoSourcesError, OutputError, WriteBackError
from dicmerge.log import get_logger
from dicmerge.output import write_text_atomic, write_words
from dicmerge.scanner import get_scanner
from dicmerge.scanner.discovery import discover_source_files


def run(
    *,
    config_path: Path | None = None,
    write_back: bool = False,
    dry_run: bool = False,
) -> dict[str, Any]:
    config = load_config(config_path)
    discovered = discover_source_files(config)

    total_sources = sum(len(files) for files in discovered.values())
    if total_sources == 0:
        raise NoSourcesError("No enabled source files found")

    stats, all_words, failed = _scan_sources(discovered)

    filtered = _apply_filters(all_words, config["filters"])
    unique = deduplicate(filtered)

    if config["output"]["sort"]:
        unique = sorted(unique, key=str.casefold)

    output_path = Path(config["output"]["path"]).expanduser()

    if not dry_run:
        _write_output(output_path, unique)

    write_back_stats: dict[str, list[tuple[str, int]]] = {}
    if write_back:
        write_back_stats = _write_back(discovered, unique, config, dry_run, failed)

    return {
        "source_stats": stats,
        "total_raw": len(all_words),
        "total_filtered": len(filtered),
        "total_unique": len(unique),
        "write_back_stats": write_back_stats,
        "output_path": str(output_path),
    }


def list_sources(config_path: Path | None = None) -> dict[str, list[Path]]:
    config = load_config(config_path)
    return discover_source_files(config)


def _scan_sources(discovered: dict[str, list[Path]]) -> tuple[dict[str, int], list[str], set[Path]]:
    stats: dict[str, int] = {}
    all_words: list[str] = []
    failed: set[Path] = set()

    for name, files in discovered.items():
        total = 0
        for path in files:
            if _should_skip_rws(name, path):
                continue
            scanner = get_scanner(path)
            try:
                words = scanner.read(path)
                all_words.extend(words)
                total += len(words)
            except Exception as e:
                failed.add(path)
                get_logger().warning("Failed to scan %s: %s", path, e)
        stats[name] = total

    return stats, all_words, failed


def _write_output(output_path: Path, unique: list[str]) -> None:
    try:
        write_words(output_path, unique)
    except OSError as e:
        raise OutputError(f"Cannot write output to {output_path}: {e}") from e


def _write_back(
    discovered: dict[str, list[Path]],
    unique: list[str],
    config: dict[str, Any],
    dry_run: bool,
    failed: set[Path],
) -> dict[str, list[tuple[str, int]]]:
    stats: dict[str, list[tuple[str, int]]] = {}

    for name, files in discovered.items():
        for path in files:
            if _should_skip_rws(name, path):
                continue
            if path in failed:
                get_logger().warning("%s: %s: skipping write-back, scan failed", name, path.name)
                continue
            if not dry_run:
                try:
                    if config["write_back"]["create_backup"]:
                        backup = path.with_suffix(path.suffix + config["write_back"]["backup_suffix"])
                        shutil.copy2(path, backup)
                    scanner = get_scanner(path)
                    content = scanner.format_output(unique)
                    write_text_atomic(path, content)
                except OSError as e:
                    raise WriteBackError(f"Cannot write back to {path}: {e}") from e
            stats.setdefault(name, []).append((path.name, len(unique)))

    return stats


def _should_skip_rws(name: str, path: Path) -> bool:
    if path.suffix != ".rws":
        return False
    get_logger().warning("%s: %s: skipping binary format (.rws)", name, path.name)
    return True


def _apply_filters(words: list[str], filters: dict[str, Any]) -> list[str]:
    min_len = filters.get("min_length", 2)
    max_len = filters.get("max_length", 64)
    allow_numbers = filters.get("allow_numbers", False)
    exclude_patterns = filters.get("exclude_patterns", [])

    compiled = [re.compile(p) for p in exclude_patterns]

    result: list[str] = []
    for w in words:
        if len(w) < min_len or len(w) > max_len:
            continue
        if not allow_numbers and any(c.isdigit() for c in w):
            continue
        if any(p.search(w) for p in compiled):
            continue
        result.append(w)
    return result
