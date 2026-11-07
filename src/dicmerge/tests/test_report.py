from datetime import datetime
from pathlib import Path

from dicmerge import report
from dicmerge.report import report_path, write_report


def test_report_path_uses_timestamp(tmp_path: Path, monkeypatch):
    monkeypatch.setattr(report, "REPORT_DIR", tmp_path)

    path = report_path(datetime(2026, 11, 7, 16, 5, 0))

    assert path == tmp_path / "dicmerge-20261107-160500.log"


def test_write_report_creates_file(tmp_path: Path):
    path = tmp_path / "sub" / "report.log"

    assert write_report(path, ["line one", "line two"]) is True
    assert path.read_text(encoding="utf-8") == "line one\nline two\n"


def test_write_report_failure_returns_false(tmp_path: Path):
    blocker = tmp_path / "blocked"
    blocker.write_text("", encoding="utf-8")

    assert write_report(blocker / "sub" / "report.log", ["x"]) is False
