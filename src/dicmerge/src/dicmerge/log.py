import logging
import logging.handlers
from pathlib import Path

LOG_DIR = Path("~/.local/share/dicmerge").expanduser()
MAX_BYTES = 1_000_000
BACKUP_COUNT = 1


def _setup_logger() -> logging.Logger:
    logger = logging.getLogger("dicmerge")
    logger.setLevel(logging.DEBUG)
    handler: logging.Handler
    try:
        LOG_DIR.mkdir(parents=True, exist_ok=True)
        handler = logging.handlers.RotatingFileHandler(
            str(LOG_DIR / "debug.log"),
            maxBytes=MAX_BYTES,
            backupCount=BACKUP_COUNT,
            encoding="utf-8",
        )
    except OSError:
        handler = logging.StreamHandler()
    handler.setLevel(logging.DEBUG)
    handler.setFormatter(logging.Formatter("%(asctime)s [%(levelname)s] %(message)s"))
    logger.addHandler(handler)
    return logger


_logger: logging.Logger | None = None


def get_logger() -> logging.Logger:
    global _logger
    if _logger is None:
        _logger = _setup_logger()
    return _logger
