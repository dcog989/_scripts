import stat
from datetime import datetime
from pathlib import Path

from dicmerge.output import expand_output_path, write_words


def test_expand_output_path_expands_timestamp(tmp_path: Path):
    pattern = str(tmp_path / "combined-%Y%m%d-%H%M%S.dic")

    path = expand_output_path(pattern, datetime(2026, 11, 7, 16, 5, 0))

    assert path == tmp_path / "combined-20261107-160500.dic"


def test_expand_output_path_leaves_plain_path(tmp_path: Path):
    path = tmp_path / "combined.dic"

    assert expand_output_path(str(path)) == path


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


def test_write_words_follows_symlink(tmp_path: Path):
    target = tmp_path / "real" / "dict.txt"
    target.parent.mkdir()
    target.write_text("old\n", encoding="utf-8")
    link = tmp_path / "link.txt"
    link.symlink_to(target)

    write_words(link, ["new"])

    assert link.is_symlink()
    assert target.read_text(encoding="utf-8") == "new\n"
