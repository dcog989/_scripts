# AGENTS.md

## Project Specifics

dicmerge, a Python package to scan, merge, and optionally write back custom user dictionaries from multiple Linux KDE applications. It lives in the `_scripts` monorepo; the root `AGENTS.md` covers repository-wide rules.

### Tech Stack

| Tool               | Version    |
| ------------------ | ---------- |
| Python             | 3.14       |
| Package manager    | uv         |
| Build backend      | hatchling  |
| Linter + formatter | ruff       |
| Type checker       | mypy       |
| Test framework     | pytest     |
| Coverage           | pytest-cov |

### Dependencies

- **Runtime**: PyYAML
- **Stdlib**: `pathlib`, `glob`, `re`, `argparse`, `shutil`, `logging`, `tempfile`
- **Dev**: ruff, mypy, pytest, pytest-cov, types-PyYAML

### Key Files

| Path                                | Purpose            |
| ----------------------------------- | ------------------ |
| `src/dicmerge/`                     | Package source     |
| `tests/`                            | pytest suite       |
| `pyproject.toml`                    | Project config     |
| `~/.config/dicmerge/config.yaml`    | User configuration |
| `~/dicmerge-output/combined.txt`    | Merged output      |
| `~/.local/share/dicmerge/debug.log` | Debug log          |

### Core Behaviors

- Scan enabled sources from config (Codebook, Firefox, Obsidian, LibreOffice, KDE Sonnet, Thunderbird, Vim, Gedit)
- Deduplicate case-insensitively (first occurrence wins)
- Output plain text, one word per line, UTF-8
- Write-back overwrites each source with the merged wordlist, creating a `.bak` backup first
- Manual execution only, no daemon or scheduler

### Command Line

```sh
dicmerge                      # Write to combined.txt
dicmerge --write-back         # Write new words back to sources
dicmerge --dry-run            # Preview only
dicmerge --list-sources       # Show discovered paths
dicmerge --version            # Show version
dicmerge --config custom.yaml # Use alternate config
```

### Exit Codes

0=Success, 1=Generic error, 2=Config error, 3=No sources, 4=Write-back failed, 5=Output unwritable

### Verification

```sh
cd src/dicmerge
uv sync
uv run ruff check
uv run ruff format --check
uv run mypy src/
uv run pytest
```

### CI

`.github/workflows/dicmerge-ci.yml` (repository root) runs ruff, mypy and pytest with a coverage gate (`fail_under = 70`) on changes under `src/dicmerge/`.
