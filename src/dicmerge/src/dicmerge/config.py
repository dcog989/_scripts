import os
from pathlib import Path
from typing import Any

import yaml

from dicmerge.exceptions import ConfigError

DEFAULT_CONFIG_PATH = Path("~/.config/dicmerge/config.yaml").expanduser()


def load_config(path: Path | None = None) -> dict[str, Any]:
    config_path = path or DEFAULT_CONFIG_PATH

    try:
        if not config_path.exists():
            default = _default_config()
            _write_config(config_path, default)
            return default
        raw = yaml.safe_load(config_path.read_text(encoding="utf-8"))
    except (yaml.YAMLError, OSError, ValueError) as e:
        raise ConfigError(f"Failed to load config {config_path}: {e}") from e

    if not isinstance(raw, dict):
        msg = f"Config must be a mapping, got {type(raw).__name__}"
        raise ConfigError(msg)

    try:
        return _normalise(raw)
    except (TypeError, AttributeError, ValueError) as e:
        raise ConfigError(f"Invalid config {config_path}: {e}") from e


def _kde_sonnet_paths() -> list[str]:
    lang = os.environ.get("LANG", "").split(".")[0]
    if lang and lang not in ("C", "POSIX", ""):
        return [f"~/.hunspell_{lang}"]
    return ["~/.hunspell_*"]


def _default_config() -> dict[str, Any]:
    return {
        "output": {
            "path": "~/dicmerge-output/combined.txt",
            "sort": True,
        },
        "sources": {
            "firefox": {
                "enabled": True,
                "paths": [
                    "~/.mozilla/firefox/*/persdict.dat",
                    "~/.config/mozilla/firefox/*/persdict.dat",
                    "~/.var/app/org.mozilla.firefox/.mozilla/firefox/*/persdict.dat",
                ],
            },
            "obsidian": {
                "enabled": True,
                "paths": [
                    "~/Documents/Obsidian/*/*.dic",
                    "~/.config/obsidian/Custom Dictionary.txt",
                ],
                "recursive": True,
            },
            "libreoffice": {
                "enabled": True,
                "paths": ["~/.config/libreoffice/4/user/wordbook/*.dic"],
            },
            "kde_sonnet": {
                "enabled": True,
                "paths": _kde_sonnet_paths(),
            },
            "thunderbird": {
                "enabled": True,
                "paths": ["~/.thunderbird/*/persdict.dat"],
            },
            "vim": {
                "enabled": True,
                "paths": [
                    "~/.vim/spell/*.add",
                    "~/.config/nvim/spell/*.add",
                ],
            },
            "gedit": {
                "enabled": True,
                "paths": ["~/.local/share/gedit/spellcheck/words"],
            },
        },
        "custom_sources": [
            {"name": "custom", "paths": ["~/my_words.txt"], "enabled": False},
        ],
        "write_back": {
            "create_backup": True,
            "backup_suffix": ".bak",
        },
        "filters": {
            "min_length": 2,
            "max_length": 64,
            "allow_numbers": False,
            "exclude_patterns": ["^[0-9]+$"],
        },
    }


def _write_config(path: Path, config: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(yaml.dump(config, default_flow_style=False), encoding="utf-8")


def _normalise(raw: dict[str, Any]) -> dict[str, Any]:
    config = _default_config()

    if "output" in raw:
        config["output"].update(raw["output"])
    if "sources" in raw:
        for name, src_cfg in raw["sources"].items():
            if name in config["sources"]:
                config["sources"][name].update(src_cfg)
            else:
                config["sources"][name] = src_cfg
        if "kde_sonnet" in raw["sources"]:
            raw_paths = raw["sources"]["kde_sonnet"].get("paths")
            if raw_paths == ["~/.hunspell_*"]:
                config["sources"]["kde_sonnet"]["paths"] = _kde_sonnet_paths()
    if "custom_sources" in raw:
        config["custom_sources"] = raw["custom_sources"]
    if "write_back" in raw:
        config["write_back"].update(raw["write_back"])
    if "filters" in raw:
        config["filters"].update(raw["filters"])

    return config
