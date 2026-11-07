from datetime import datetime
from pathlib import Path

from dicmerge.log import get_logger

REPORT_DIR = Path("~/dicmerge").expanduser()
_TIMESTAMP_FORMAT = "%Y%m%d-%H%M%S"


def report_path(now: datetime | None = None) -> Path:
    stamp = (now or datetime.now()).strftime(_TIMESTAMP_FORMAT)
    return REPORT_DIR / f"dicmerge-{stamp}.log"


def write_report(path: Path, lines: list[str]) -> bool:
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
    except OSError as e:
        get_logger().warning("Failed to write report %s: %s", path, e)
        return False
    return True
