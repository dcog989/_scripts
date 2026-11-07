# dicmerge

Scan multiple applications for custom user dictionaries, merge them into a single wordlist, and optionally write new words back to each source.

Part of the [`_scripts`](../../README.md) collection.

## Install

```sh
uv tool install ./src/dicmerge    # from the repository root
```

## Usage

```sh
dicmerge                      # Merge and write ~/dicmerge-output/combined.txt
dicmerge --dry-run            # Preview only, no files written
dicmerge --write-back         # Overwrite each source with the merged wordlist
dicmerge --list-sources       # Show discovered dictionary files
dicmerge --version            # Show version
dicmerge --config custom.yaml # Use an alternate config file
```

On first run, `~/.config/dicmerge/config.yaml` is created automatically with default settings.

## Sources

| Source      | Path(s)                                                                                                                                           |
| ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| Codebook    | `~/.config/codebook/codebook.toml`                                                                                                                |
| Firefox     | `~/.mozilla/firefox/*/persdict.dat`, `~/.config/mozilla/firefox/*/persdict.dat`, `~/.var/app/org.mozilla.firefox/.mozilla/firefox/*/persdict.dat` |
| Thunderbird | `~/.thunderbird/*/persdict.dat`                                                                                                                   |
| Obsidian    | `~/Documents/Obsidian/*/*.dic`, `~/.config/obsidian/Custom Dictionary.txt`                                                                        |
| LibreOffice | `~/.config/libreoffice/4/user/wordbook/*.dic`                                                                                                     |
| KDE Sonnet  | `~/.hunspell_<LANG>` (falls back to `~/.hunspell_*`)                                                                                              |
| Vim/Neovim  | `~/.vim/spell/*.add`, `~/.config/nvim/spell/*.add`                                                                                                |
| Gedit       | `~/.local/share/gedit/spellcheck/words`                                                                                                           |

Custom sources can be added under `custom_sources` in the config file.

## Output

Written to `~/dicmerge-output/combined.txt` (configurable under `output`): one word per line, deduplicated case-insensitively, sorted, UTF-8.

## Write-back

`--write-back` overwrites each source dictionary with the merged wordlist. Each original file is backed up with a `.bak` suffix before it is modified.

---

## Development

Run from this directory:

```sh
uv sync                  # Create/refresh the dev environment
uv run dicmerge          # Run from source
uv run ruff check        # Lint
uv run ruff format .     # Format
uv run mypy src/         # Type check
uv run pytest            # Test
uv clean                 # Clean build artifacts
```

## License

MIT. See the repository [`LICENSE`](../../LICENSE).
