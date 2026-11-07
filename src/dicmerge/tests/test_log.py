import logging
import logging.handlers
from pathlib import Path

from dicmerge.log import get_logger


def _reset_logger(monkeypatch, log_dir: Path) -> None:
    monkeypatch.setattr("dicmerge.log.LOG_DIR", log_dir)
    monkeypatch.setattr("dicmerge.log._logger", None)
    logging.getLogger("dicmerge").handlers.clear()


def test_get_logger_uses_rotating_file_handler(tmp_path: Path, monkeypatch):
    _reset_logger(monkeypatch, tmp_path / "dicmerge")

    logger = get_logger()

    assert isinstance(logger.handlers[-1], logging.handlers.RotatingFileHandler)


def test_get_logger_falls_back_when_log_dir_is_unwritable(tmp_path: Path, monkeypatch):
    blocker = tmp_path / "blocked"
    blocker.write_text("", encoding="utf-8")
    _reset_logger(monkeypatch, blocker / "dicmerge")

    logger = get_logger()

    assert not isinstance(logger.handlers[-1], logging.FileHandler)
    logger.warning("does not raise")
