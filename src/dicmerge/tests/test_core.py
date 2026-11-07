from pathlib import Path

import yaml

from dicmerge.core import _apply_filters, _should_skip_rws, run
from dicmerge.exceptions import NoSourcesError, OutputError, WriteBackError
from dicmerge.scanner.firefox import FirefoxScanner


def test_should_skip_rws(tmp_path: Path):
    assert _should_skip_rws("kde_sonnet", tmp_path / "foo.rws") is True
    assert _should_skip_rws("kde_sonnet", tmp_path / "foo.txt") is False


def test_run_output_failure_raises_output_error(tmp_path: Path, monkeypatch):
    import pytest

    config_path, src, _ = _make_config(tmp_path)
    d = src / "firefox" / "default"
    d.mkdir(parents=True)
    (d / "persdict.dat").write_text("foo\n", encoding="utf-8")

    def _fail_write(path, words):
        raise OSError("disk full")

    monkeypatch.setattr("dicmerge.core.write_words", _fail_write)

    with pytest.raises(OutputError):
        run(config_path=config_path)


def test_apply_filters_min_length():
    words = ["a", "ab", "abc"]
    result = _apply_filters(words, {"min_length": 2})
    assert result == ["ab", "abc"]


def test_apply_filters_max_length():
    words = ["a", "ab", "abc", "abcd"]
    result = _apply_filters(words, {"min_length": 1, "max_length": 3})
    assert result == ["a", "ab", "abc"]


def test_apply_filters_numbers_not_allowed():
    words = ["foo", "bar123", "baz"]
    result = _apply_filters(words, {"allow_numbers": False})
    assert result == ["foo", "baz"]


def test_apply_filters_numbers_allowed():
    words = ["foo", "bar123", "baz"]
    result = _apply_filters(words, {"allow_numbers": True})
    assert result == ["foo", "bar123", "baz"]


def test_apply_filters_exclude_pattern():
    words = ["foo", "bar", "baz123", "qux"]
    result = _apply_filters(
        words,
        {"exclude_patterns": [r"\d"]},
    )
    assert result == ["foo", "bar", "qux"]


def test_apply_filters_combined():
    words = ["a", "foo", "bar123", "toolongword", "baz", "42"]
    result = _apply_filters(
        words,
        {
            "min_length": 2,
            "max_length": 5,
            "allow_numbers": False,
            "exclude_patterns": [],
        },
    )
    assert result == ["foo", "baz"]


def _make_config(tmp_path: Path) -> tuple[Path, Path, Path]:
    src = tmp_path / "sources"
    out = tmp_path / "output"

    cfg = {
        "output": {
            "path": str(out / "combined.txt"),
            "sort": False,
        },
        "sources": {
            "firefox": {
                "enabled": True,
                "paths": [str(src / "firefox/*/persdict.dat")],
            },
            "obsidian": {"enabled": False, "paths": []},
            "libreoffice": {"enabled": False, "paths": []},
            "kde_sonnet": {"enabled": False, "paths": []},
            "thunderbird": {"enabled": False, "paths": []},
            "vim": {"enabled": False, "paths": []},
            "gedit": {"enabled": False, "paths": []},
        },
        "custom_sources": [],
        "write_back": {
            "create_backup": True,
            "backup_suffix": ".bak",
        },
        "filters": {
            "min_length": 1,
            "max_length": 100,
            "allow_numbers": True,
            "exclude_patterns": [],
        },
    }
    config_path = tmp_path / "config.yaml"
    config_path.write_text(yaml.dump(cfg), encoding="utf-8")
    return config_path, src, out


def test_run_basic(tmp_path: Path):
    config_path, src, out = _make_config(tmp_path)
    d = src / "firefox" / "default"
    d.mkdir(parents=True)
    (d / "persdict.dat").write_text("foo\nbar\nbaz\n", encoding="utf-8")

    result = run(config_path=config_path)

    assert result["source_stats"]["firefox"] == 3
    assert result["total_unique"] == 3
    assert (out / "combined.txt").exists()
    assert (out / "combined.txt").read_text(encoding="utf-8") == "foo\nbar\nbaz\n"


def test_run_merges_multiple_sources(tmp_path: Path):
    config_path, src, _ = _make_config(tmp_path)
    (src / "firefox" / "default").mkdir(parents=True)
    (src / "firefox" / "default" / "persdict.dat").write_text("foo\nbar\n", encoding="utf-8")

    cfg = yaml.safe_load(config_path.read_text(encoding="utf-8"))
    cfg["sources"]["libreoffice"] = {
        "enabled": True,
        "paths": [str(src / "libreoffice/*.dic")],
    }
    config_path.write_text(yaml.dump(cfg), encoding="utf-8")
    (src / "libreoffice").mkdir(parents=True)
    (src / "libreoffice" / "custom.dic").write_text(
        "OOoUserDict1\nlang: en-US\ntype: positive\nreplacement: \nbar\nbaz\n",
        encoding="utf-8",
    )

    result = run(config_path=config_path)

    assert result["source_stats"]["firefox"] == 2
    assert result["source_stats"]["libreoffice"] == 2
    assert result["total_unique"] == 3


def test_run_deduplicates(tmp_path: Path):
    config_path, src, _ = _make_config(tmp_path)
    d = src / "firefox" / "default"
    d.mkdir(parents=True)
    (d / "persdict.dat").write_text("foo\nbar\nfoo\nBAR\n", encoding="utf-8")

    result = run(config_path=config_path)

    assert result["total_unique"] == 2
    assert result["total_raw"] == 4


def test_run_sorts_output(tmp_path: Path):
    config_path, src, out = _make_config(tmp_path)
    d = src / "firefox" / "default"
    d.mkdir(parents=True)
    (d / "persdict.dat").write_text("gamma\nAlpha\nbeta\n", encoding="utf-8")

    cfg = yaml.safe_load(config_path.read_text(encoding="utf-8"))
    cfg["output"]["sort"] = True
    config_path.write_text(yaml.dump(cfg), encoding="utf-8")

    result = run(config_path=config_path)

    assert result["total_unique"] == 3
    assert (out / "combined.txt").read_text(encoding="utf-8") == "Alpha\nbeta\ngamma\n"


def test_run_dry_run_does_not_write(tmp_path: Path):
    config_path, src, out = _make_config(tmp_path)
    d = src / "firefox" / "default"
    d.mkdir(parents=True)
    (d / "persdict.dat").write_text("foo\nbar\n", encoding="utf-8")

    result = run(config_path=config_path, dry_run=True)

    assert result["total_unique"] == 2
    assert not (out / "combined.txt").exists()


def test_run_no_sources_raises_error(tmp_path: Path):
    config_path, src, _ = _make_config(tmp_path)
    cfg = yaml.safe_load(config_path.read_text(encoding="utf-8"))
    cfg["sources"]["firefox"]["paths"] = [str(src / "nonexistent/*.dat")]
    config_path.write_text(yaml.dump(cfg), encoding="utf-8")

    import pytest

    with pytest.raises(NoSourcesError):
        run(config_path=config_path)


def test_run_write_back_overwrites_files(tmp_path: Path):
    config_path, src, _ = _make_config(tmp_path)

    firefox_dir = src / "firefox" / "default"
    firefox_dir.mkdir(parents=True)
    ff_file = firefox_dir / "persdict.dat"
    ff_file.write_text("foo\n", encoding="utf-8")

    cfg = yaml.safe_load(config_path.read_text(encoding="utf-8"))
    cfg["sources"]["libreoffice"] = {
        "enabled": True,
        "paths": [str(src / "libreoffice/*.dic")],
    }
    cfg["write_back"]["create_backup"] = False
    config_path.write_text(yaml.dump(cfg), encoding="utf-8")

    lo_dir = src / "libreoffice"
    lo_dir.mkdir(parents=True)
    lo_file = lo_dir / "custom.dic"
    lo_file.write_text(
        "OOoUserDict1\nlang: en-US\ntype: positive\nreplacement: \nbar\nbaz\n",
        encoding="utf-8",
    )

    result = run(config_path=config_path, write_back=True)

    assert result["write_back_stats"]["firefox"] == [("persdict.dat", 3)]
    assert result["write_back_stats"]["libreoffice"] == [("custom.dic", 3)]
    assert ff_file.read_text(encoding="utf-8") == "foo\nbar\nbaz\n"
    assert lo_file.read_text(encoding="utf-8") == (
        "OOoUserDict1\nlang: en-US\ntype: positive\nreplacement: \nfoo\nbar\nbaz\n"
    )


def test_run_write_back_creates_backup(tmp_path: Path):
    config_path, src, _ = _make_config(tmp_path)

    firefox_dir = src / "firefox" / "default"
    firefox_dir.mkdir(parents=True)
    ff_file = firefox_dir / "persdict.dat"
    ff_file.write_text("foo\n", encoding="utf-8")

    cfg = yaml.safe_load(config_path.read_text(encoding="utf-8"))
    cfg["sources"]["libreoffice"] = {
        "enabled": True,
        "paths": [str(src / "libreoffice/*.dic")],
    }
    cfg["write_back"]["create_backup"] = True
    config_path.write_text(yaml.dump(cfg), encoding="utf-8")

    lo_dir = src / "libreoffice"
    lo_dir.mkdir(parents=True)
    lo_file = lo_dir / "custom.dic"
    lo_file.write_text(
        "OOoUserDict1\nlang: en-US\ntype: positive\nreplacement: \nbar\n",
        encoding="utf-8",
    )

    run(config_path=config_path, write_back=True)

    assert (firefox_dir / "persdict.dat.bak").exists()
    assert (lo_dir / "custom.dic.bak").exists()
    assert (firefox_dir / "persdict.dat.bak").read_text(encoding="utf-8") == "foo\n"


def test_run_write_back_flag_wins_over_config(tmp_path: Path):
    config_path, src, _ = _make_config(tmp_path)

    firefox_dir = src / "firefox" / "default"
    firefox_dir.mkdir(parents=True)
    ff_file = firefox_dir / "persdict.dat"
    ff_file.write_text("foo\n", encoding="utf-8")

    result = run(config_path=config_path, write_back=True)

    assert result["write_back_stats"] == {"firefox": [("persdict.dat", 1)]}
    assert ff_file.read_text(encoding="utf-8") == "foo\n"


def test_run_write_back_refreshes_backup(tmp_path: Path):
    config_path, src, _ = _make_config(tmp_path)

    firefox_dir = src / "firefox" / "default"
    firefox_dir.mkdir(parents=True)
    ff_file = firefox_dir / "persdict.dat"
    ff_file.write_text("foo\n", encoding="utf-8")

    run(config_path=config_path, write_back=True)
    assert (firefox_dir / "persdict.dat.bak").read_text(encoding="utf-8") == "foo\n"

    ff_file.write_text("foo\nbar\n", encoding="utf-8")
    run(config_path=config_path, write_back=True)
    assert (firefox_dir / "persdict.dat.bak").read_text(encoding="utf-8") == "foo\nbar\n"


def test_run_write_back_dry_run_reports_targets_without_writing(tmp_path: Path):
    config_path, src, _ = _make_config(tmp_path)

    firefox_dir = src / "firefox" / "default"
    firefox_dir.mkdir(parents=True)
    ff_file = firefox_dir / "persdict.dat"
    ff_file.write_text("foo\nbar\n", encoding="utf-8")

    result = run(config_path=config_path, write_back=True, dry_run=True)

    assert result["write_back_stats"] == {"firefox": [("persdict.dat", 2)]}
    assert ff_file.read_text(encoding="utf-8") == "foo\nbar\n"
    assert not (firefox_dir / "persdict.dat.bak").exists()


def test_run_write_back_backup_failure_raises_writeback_error(tmp_path: Path, monkeypatch):
    import shutil

    import pytest

    config_path, src, _ = _make_config(tmp_path)

    firefox_dir = src / "firefox" / "default"
    firefox_dir.mkdir(parents=True)
    ff_file = firefox_dir / "persdict.dat"
    ff_file.write_text("foo\nbar\n", encoding="utf-8")

    def _fail_copy2(src_path, dst_path):
        raise OSError("backup failed")

    monkeypatch.setattr(shutil, "copy2", _fail_copy2)

    with pytest.raises(WriteBackError):
        run(config_path=config_path, write_back=True)


def test_run_write_back_skips_unreadable_source(tmp_path: Path, monkeypatch):
    config_path, src, _ = _make_config(tmp_path)

    firefox_dir = src / "firefox" / "default"
    firefox_dir.mkdir(parents=True)
    ff_file = firefox_dir / "persdict.dat"
    ff_file.write_text("foo\n", encoding="utf-8")

    def _fail_read(self, path):
        raise OSError("cannot read")

    monkeypatch.setattr(FirefoxScanner, "read", _fail_read)

    result = run(config_path=config_path, write_back=True)

    assert result["write_back_stats"] == {}
    assert ff_file.read_text(encoding="utf-8") == "foo\n"
    assert not (firefox_dir / "persdict.dat.bak").exists()


def test_run_skips_file_with_nul_bytes(tmp_path: Path):
    config_path, src, out = _make_config(tmp_path)

    d = src / "firefox" / "default"
    d.mkdir(parents=True)
    (d / "persdict.dat").write_bytes("foo\n".encode("utf-16-le"))

    result = run(config_path=config_path)

    assert result["source_stats"]["firefox"] == 0
    assert (out / "combined.txt").read_text(encoding="utf-8") == ""
