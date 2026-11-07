# dicmerge

Scan multiple applications for custom user dictionaries, merge them into a single wordlist, and optionally write new words back to each source.

Part of the [`_scripts`](../../README.md) collection.

## Install

```sh
uv tool install ./src/dicmerge    # from the repository root
```

## Usage

```sh
dicmerge                      # Preview, then ask to write output and all sources
dicmerge --list-sources       # Show discovered dictionary files
dicmerge --version            # Show version
```

`dicmerge` scans, prints the preview, then asks `Write changes? [y/N]`; Enter or `n` writes nothing. Answering `y` writes the combined wordlist and overwrites every source dictionary (each gets a `.dicmerge.bak` copy first).

On first run, `~/.config/dicmerge/config.yaml` is created automatically with default settings.

Each run also writes the report to `~/dicmerge/dicmerge-<timestamp>.log`.

## Sources

| Source      | Path(s)                                                                                                                                           |
| ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| Codebook    | `~/.config/codebook/codebook.toml`                                                                                                                |
| Firefox     | `~/.mozilla/firefox/*/persdict.dat`, `~/.config/mozilla/firefox/*/persdict.dat`, `~/.var/app/org.mozilla.firefox/.mozilla/firefox/*/persdict.dat` |
| Thunderbird | `~/.thunderbird/*/persdict.dat`                                                                                                                   |
| Obsidian    | `~/Documents/Obsidian/*/*.dic`, `~/.config/obsidian/Custom Dictionary.txt`                                                                        |
| LibreOffice | `~/.config/libreoffice/4/user/wordbook/*.dic`                                                                                                     |
| MarkdownRS  | `~/.local/share/com.markdownrs.editor/custom-spelling.dic`                                                                                        |
| OpenCode    | `~/.config/ai.opencode.desktop/Custom Dictionary.txt`                                                                                             |
| KDE Sonnet  | `~/.hunspell_<LANG>` (falls back to `~/.hunspell_*`)                                                                                              |
| Vim/Neovim  | `~/.vim/spell/*.add`, `~/.config/nvim/spell/*.add`                                                                                                |
| Gedit       | `~/.local/share/gedit/spellcheck/words`                                                                                                           |

Custom sources can be added under `custom_sources` in the config file.

## Output

Written to `~/dicmerge-output/combined.txt` (configurable under `output`): one word per line, deduplicated case-insensitively, sorted, UTF-8.

## Write-back

`dicmerge` runs in two phases: preview, then write on confirmation. Each source file is backed up with a `.dicmerge.bak` suffix before it is overwritten.

Filters (`min_length`, `max_length`, `allow_numbers`, `exclude_patterns`) apply to the output file only. Write-back always keeps every scanned word, so filtered words are never deleted from a source. If a dictionary app is running, the preview warns you to close it first.

---

## Development

Run from this directory:

```sh
uv sync                      # Create/refresh the dev environment
uv tool upgrade --all        # global uv-installed tools
uv tool upgrade dicmerge     # just dicmerge
uv lock --upgrade && uv sync # this project's Python deps (run in src/dicmerge)
uv run dicmerge              # Run from source
uv run ruff check            # Lint
uv run ruff format .         # Format
uv run mypy src/             # Type check
uv run pytest                # Test
uv clean                     # Clean build artifacts
```

## License

MIT. See the repository [`LICENSE`](../../LICENSE).
