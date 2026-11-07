import glob
import hashlib
from pathlib import Path
from typing import Any

from dicmerge.log import get_logger


def _is_backup(path: Path) -> bool:
    parent = path.parent.name.casefold()
    if parent.endswith("-backup") or "-backup-crashrecovery-" in parent:
        return True
    return path.suffix == ".bak"


def _content_hash(path: Path) -> str | None:
    try:
        return hashlib.sha256(path.read_bytes()).hexdigest()
    except OSError:
        return None


def _drop_duplicate_content(files: list[Path]) -> list[Path]:
    seen: dict[str, Path] = {}
    unique: list[Path] = []
    for path in files:
        digest = _content_hash(path)
        if digest is not None and digest in seen:
            get_logger().info("%s: skipping duplicate of %s", path, seen[digest])
            continue
        if digest is not None:
            seen[digest] = path
        unique.append(path)
    return unique


def _discover_paths(patterns: list[str], *, recursive: bool) -> list[Path]:
    files: list[Path] = []
    for pattern in patterns:
        matches = glob.glob(str(Path(pattern).expanduser()), recursive=recursive)
        files.extend(p for p in (Path(m) for m in matches) if p.is_file() and not _is_backup(p))
    return _drop_duplicate_content(sorted(set(files)))


def discover_source_files(config: dict[str, Any]) -> dict[str, list[Path]]:
    discovered: dict[str, list[Path]] = {}

    for name, source in config["sources"].items():
        if not source.get("enabled", True):
            continue
        discovered[name] = _discover_paths(source["paths"], recursive=source.get("recursive", False))

    for entry in config.get("custom_sources", []):
        if not entry.get("enabled", False):
            continue
        discovered[entry["name"]] = _discover_paths(entry["paths"], recursive=False)

    return discovered
