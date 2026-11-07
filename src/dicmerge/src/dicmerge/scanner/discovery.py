import glob
import hashlib
from pathlib import Path

from dicmerge.config import Config
from dicmerge.log import get_logger

_BACKUP_MARKERS = ("-backup", "-back-")


def _is_backup(path: Path) -> bool:
    parent = path.parent.name.casefold()
    if any(marker in parent for marker in _BACKUP_MARKERS):
        return True
    return path.suffix == ".bak"


def _content_hash(path: Path) -> str | None:
    try:
        with path.open("rb") as f:
            return hashlib.file_digest(f, "sha256").hexdigest()
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


def discover_source_files(config: Config) -> dict[str, list[Path]]:
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
