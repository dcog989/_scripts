import sys
from pathlib import Path

import pytest
import yaml

from dicmerge.cli import main
from dicmerge.exceptions import ConfigError


def _write_config(tmp_path: Path) -> Path:
    cfg = {
        "output": {"path": str(tmp_path / "out" / "combined.txt"), "sort": False},
        "sources": {
            "firefox": {"enabled": True, "paths": [str(tmp_path / "src/*/persdict.dat")]},
            "obsidian": {"enabled": False, "paths": []},
            "libreoffice": {"enabled": False, "paths": []},
            "kde_sonnet": {"enabled": False, "paths": []},
            "thunderbird": {"enabled": False, "paths": []},
            "vim": {"enabled": False, "paths": []},
            "gedit": {"enabled": False, "paths": []},
        },
        "custom_sources": [],
        "write_back": {"create_backup": True, "backup_suffix": ".bak"},
        "filters": {
            "min_length": 1,
            "max_length": 100,
            "allow_numbers": True,
            "exclude_patterns": [],
        },
    }
    config_path = tmp_path / "config.yaml"
    config_path.write_text(yaml.dump(cfg), encoding="utf-8")
    return config_path


def test_cli_version(capsys: pytest.CaptureFixture[str], monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(sys, "argv", ["dicmerge", "--version"])
    with pytest.raises(SystemExit) as exc:
        main()
    assert exc.value.code == 0
    assert "dicmerge" in capsys.readouterr().out


def test_cli_prints_default_config_path(capsys: pytest.CaptureFixture[str], monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(sys, "argv", ["dicmerge", "--config"])
    main()
    assert "Config path:" in capsys.readouterr().out


def test_cli_missing_config_exits_config_error(
    tmp_path: Path, capsys: pytest.CaptureFixture[str], monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(sys, "argv", ["dicmerge", "--config", str(tmp_path / "nope.yaml")])
    with pytest.raises(SystemExit) as exc:
        main()
    assert exc.value.code == ConfigError.exit_code
    assert "Config file not found" in capsys.readouterr().out


def test_cli_config_directory_exits_config_error(
    tmp_path: Path, capsys: pytest.CaptureFixture[str], monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(sys, "argv", ["dicmerge", "--config", str(tmp_path)])
    with pytest.raises(SystemExit) as exc:
        main()
    assert exc.value.code == ConfigError.exit_code
    assert "Config file not found" in capsys.readouterr().out


def test_cli_list_sources(tmp_path: Path, capsys: pytest.CaptureFixture[str], monkeypatch: pytest.MonkeyPatch) -> None:
    config = _write_config(tmp_path)
    src = tmp_path / "src" / "default"
    src.mkdir(parents=True)
    (src / "persdict.dat").write_text("foo\n", encoding="utf-8")

    monkeypatch.setattr(sys, "argv", ["dicmerge", "--config", str(config), "--list-sources"])
    main()

    out = capsys.readouterr().out
    assert "Discovered Sources" in out
    assert "firefox" in out


def test_cli_dry_run(tmp_path: Path, capsys: pytest.CaptureFixture[str], monkeypatch: pytest.MonkeyPatch) -> None:
    config = _write_config(tmp_path)
    src = tmp_path / "src" / "default"
    src.mkdir(parents=True)
    (src / "persdict.dat").write_text("foo\nbar\n", encoding="utf-8")

    monkeypatch.setattr(sys, "argv", ["dicmerge", "--config", str(config), "--dry-run"])
    main()

    out = capsys.readouterr().out
    assert "Dry run mode" in out
    assert "Done." in out
    assert not (tmp_path / "out" / "combined.txt").exists()
