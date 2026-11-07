import re
import shutil
import subprocess
from pathlib import Path
from typing import NamedTuple, TypedDict

from dicmerge.config import Config, FiltersConfig, load_config
from dicmerge.dedup import deduplicate
from dicmerge.exceptions import NoSourcesError, OutputError, WriteBackError
from dicmerge.log import get_logger
from dicmerge.output import write_text_atomic, write_words
from dicmerge.scanner import get_scanner
from dicmerge.scanner.discovery import discover_source_files

_APP_PROCESSES: dict[str, tuple[str, ...]] = {
    "firefox": ("firefox",),
    "thunderbird": ("thunderbird",),
    "libreoffice": ("soffice.bin",),
    "gedit": ("gedit",),
    "obsidian": ("obsidian",),
}


class RunResult(TypedDict):
    source_stats: dict[str, int]
    failed_stats: dict[str, int]
    total_raw: int
    total_filtered: int
    total_unique: int
    write_back_stats: dict[str, list[tuple[str, int]]]
    output_path: str
    warnings: list[str]


class Prepared(TypedDict):
    config: Config
    discovered: dict[str, list[Path]]
    scanned: dict[Path, list[str]]
    failed: set[Path]
    source_stats: dict[str, int]
    failed_stats: dict[str, int]
    warnings: list[str]
    total_raw: int
    total_filtered: int
    output_words: list[str]
    write_back_words: list[str]
    output_path: Path
    write_back_preview: dict[str, list[tuple[str, int]]]


class _ScanResult(NamedTuple):
    stats: dict[str, int]
    failed_stats: dict[str, int]
    scanned: dict[Path, list[str]]
    failed: set[Path]
    words: list[str]


def prepare(config_path: Path | None = None) -> Prepared:
    config = load_config(config_path)
    discovered = discover_source_files(config)

    if sum(len(files) for files in discovered.values()) == 0:
        raise NoSourcesError("No enabled source files found")

    scanned = _scan_sources(discovered)
    if not scanned.scanned:
        raise NoSourcesError("No readable source files found")

    filtered = _apply_filters(scanned.words, config["filters"])
    output_words = deduplicate(filtered)
    write_back_words = deduplicate(scanned.words)

    if config["output"]["sort"]:
        output_words = sorted(output_words, key=str.casefold)
        write_back_words = sorted(write_back_words, key=str.casefold)

    output_path = Path(config["output"]["path"]).expanduser()
    preview = _write_back(
        discovered,
        write_back_words,
        config,
        dry_run=True,
        failed=scanned.failed,
        scanned=scanned.scanned,
    )

    return {
        "config": config,
        "discovered": discovered,
        "scanned": scanned.scanned,
        "failed": scanned.failed,
        "source_stats": scanned.stats,
        "failed_stats": scanned.failed_stats,
        "warnings": _running_app_warnings(discovered),
        "total_raw": len(scanned.words),
        "total_filtered": len(filtered),
        "output_words": output_words,
        "write_back_words": write_back_words,
        "output_path": output_path,
        "write_back_preview": preview,
    }


def write(
    prepared: Prepared,
    *,
    write_back: bool = False,
    dry_run: bool = False,
) -> RunResult:
    if not dry_run:
        _write_output(prepared["output_path"], prepared["output_words"])

    write_back_stats: dict[str, list[tuple[str, int]]] = {}
    if write_back:
        write_back_stats = _write_back(
            prepared["discovered"],
            prepared["write_back_words"],
            prepared["config"],
            dry_run=dry_run,
            failed=prepared["failed"],
            scanned=prepared["scanned"],
        )

    return {
        "source_stats": prepared["source_stats"],
        "failed_stats": prepared["failed_stats"],
        "total_raw": prepared["total_raw"],
        "total_filtered": prepared["total_filtered"],
        "total_unique": len(prepared["output_words"]),
        "write_back_stats": write_back_stats,
        "output_path": str(prepared["output_path"]),
        "warnings": prepared["warnings"],
    }


def run(
    *,
    config_path: Path | None = None,
    write_back: bool = False,
    dry_run: bool = False,
) -> RunResult:
    return write(prepare(config_path), write_back=write_back, dry_run=dry_run)


def list_sources(config_path: Path | None = None) -> dict[str, list[Path]]:
    config = load_config(config_path)
    return discover_source_files(config)


def _scan_sources(discovered: dict[str, list[Path]]) -> _ScanResult:
    stats: dict[str, int] = {}
    failed_stats: dict[str, int] = {}
    scanned: dict[Path, list[str]] = {}
    failed: set[Path] = set()
    all_words: list[str] = []

    for name, files in discovered.items():
        total = 0
        for path in files:
            if _should_skip_rws(name, path):
                continue
            try:
                words = get_scanner(path).read(path)
            except Exception as e:
                failed.add(path)
                failed_stats[name] = failed_stats.get(name, 0) + 1
                get_logger().warning("Failed to scan %s: %s", path, e)
                continue
            scanned[path] = words
            all_words.extend(words)
            total += len(words)
        stats[name] = total

    return _ScanResult(stats, failed_stats, scanned, failed, all_words)


def _running_app_warnings(discovered: dict[str, list[Path]]) -> list[str]:
    pgrep = shutil.which("pgrep")
    if pgrep is None:
        return []
    warnings: list[str] = []
    for name, processes in _APP_PROCESSES.items():
        if discovered.get(name) and any(_process_running(pgrep, process) for process in processes):
            warnings.append(f"{name} is running; close it before write-back")
    return warnings


def _process_running(pgrep: str, name: str) -> bool:
    result = subprocess.run(  # noqa: S603
        [pgrep, "-x", name],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    return result.returncode == 0


def _write_output(output_path: Path, unique: list[str]) -> None:
    try:
        write_words(output_path, unique)
    except OSError as e:
        raise OutputError(f"Cannot write output to {output_path}: {e}") from e


def _write_back(
    discovered: dict[str, list[Path]],
    unique: list[str],
    config: Config,
    *,
    dry_run: bool,
    failed: set[Path],
    scanned: dict[Path, list[str]],
) -> dict[str, list[tuple[str, int]]]:
    stats: dict[str, list[tuple[str, int]]] = {}
    errors: list[str] = []

    for name, files in discovered.items():
        for path in files:
            if _should_skip_rws(name, path):
                continue
            if path in failed:
                get_logger().warning("%s: %s: skipping write-back, scan failed", name, path.name)
                continue
            scanner = get_scanner(path)
            new_words = _count_new_words(scanned.get(path, []), unique)
            if not dry_run:
                try:
                    if config["write_back"]["create_backup"]:
                        backup = path.with_suffix(path.suffix + config["write_back"]["backup_suffix"])
                        shutil.copy2(path, backup)
                    content = scanner.format_output(path, unique)
                    write_text_atomic(path, content)
                except OSError as e:
                    errors.append(f"{path}: {e}")
                    continue
            stats.setdefault(name, []).append((path.name, new_words))

    if errors:
        raise WriteBackError("Cannot write back to: " + "; ".join(errors))
    return stats


def _count_new_words(existing_words: list[str], unique: list[str]) -> int:
    existing = {word.casefold() for word in existing_words}
    return sum(1 for word in unique if word.casefold() not in existing)


def _should_skip_rws(name: str, path: Path) -> bool:
    if path.suffix != ".rws":
        return False
    get_logger().warning("%s: %s: skipping binary format (.rws)", name, path.name)
    return True


def _apply_filters(words: list[str], filters: FiltersConfig) -> list[str]:
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
