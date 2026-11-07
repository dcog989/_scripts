import stat
from pathlib import Path

from dicmerge.output import write_words


def test_write_words_creates_file(tmp_path: Path):
    path = tmp_path / "combined.txt"
    write_words(path, ["foo", "bar", "baz"])
    assert path.read_text(encoding="utf-8") == "foo\nbar\nbaz\n"


def test_write_words_empty_list(tmp_path: Path):
    path = tmp_path / "combined.txt"
    write_words(path, [])
    assert path.read_text(encoding="utf-8") == ""


def test_write_words_creates_parent_dirs(tmp_path: Path):
    path = tmp_path / "sub" / "nested" / "combined.txt"
    write_words(path, ["foo"])
    assert path.exists()
    assert path.read_text(encoding="utf-8") == "foo\n"


def test_write_words_overwrites_existing(tmp_path: Path):
    path = tmp_path / "combined.txt"
    path.write_text("old\n", encoding="utf-8")
    write_words(path, ["new"])
    assert path.read_text(encoding="utf-8") == "new\n"


def test_write_words_new_file_is_world_readable(tmp_path: Path):
    path = tmp_path / "combined.txt"
    write_words(path, ["foo"])
    assert stat.S_IMODE(path.stat().st_mode) == 0o644


def test_write_words_preserves_existing_mode(tmp_path: Path):
    path = tmp_path / "combined.txt"
    path.write_text("old\n", encoding="utf-8")
    path.chmod(0o640)
    write_words(path, ["new"])
    assert stat.S_IMODE(path.stat().st_mode) == 0o640
