# scripts

A collection of scripts for maintaining Arch/CachyOS, pacman/AUR/git repositories, etc.

## Contents

| Script | Type | Purpose |
| --- | --- | --- |
| [`src/big-files.fish`](#big-files)                      | fish function | List files above a size threshold, largest first. |
| [`src/git-maintenance.fish`](#git-maintenance)          | fish function | Optimize and report issues for every git repo under a directory tree. |
| [`src/health-check.sh`](#health-check)                  | shell script  | Read-only report of system-wide issues. |
| [`src/install-apps.sh`](#install-apps)                  | shell script  | Install a fixed set of repo and AUR packages. |
| [`src/lact-gaming.sh`](#lact-gaming)                    | shell script  | LACT Gaming hook: switch monitor refresh rate and park/restore apps. |
| [`src/last-installed.fish`](#last-installed)            | fish function | List recently installed pacman/AUR apps. |
| [`src/long-files.fish`](#long-files)                    | fish function | List text files by line length, grouped by directory. |
| [`src/music/artists-with-flac.sh`](#music)              | shell script  | List artists under `/mnt/data/Music` that contain FLAC files. |
| [`src/music/flac-conversion.py`](#music)                | Python script | Cap hi-res FLAC at 16-bit / 48 kHz into a separate target tree. |
| [`src/music/music-48k-move.sh`](#music)                 | shell script  | Replace library files with their converted 48 kHz counterparts (dry run by default). |
| [`src/old-files.fish`](#old-files)                      | fish function | List files older than a number of days. Use `-d` for directories. |
| [`src/opencode-maintenance.sh`](#opencode-maintenance)  | shell script  | Prune OpenCode DB rows and snapshots for dead projects, and rotate its log. |
| [`src/repository-clean.fish`](#repository-clean)        | fish function | List then clean pacman/AUR package leftovers (orphans, caches, unneeded deps). |

---

## Install Fish Functions

```sh
ln -sf /path/to/src.fish ~/.config/fish/functions/   # symlink to fish functions directory
```

## Install Shell Scripts

```sh
chmod +x /path/to/src.sh           # mark executable
ln -sf /path/to/src ~/.local/bin/  # symlink to `PATH`. Note: extension not needed here.
```

---

## repository-clean

Lists and cleans pacman/AUR package leftovers. Prints a report, asks for confirmation, then cleans.

Cleans:

- **Orphans** — packages installed as dependencies that are no longer required (`pacman -Qdtq`).
- **Package cache** — prunes `/var/cache/pacman/pkg` with `paccache -k 3`, then drops every cached version of an uninstalled package. The report previews what both steps reclaim.
- **Stale download dirs** — removes the `download-XXXXXX` temp dirs libalpm leaks after an interrupted download. `pacman -Sc` fails with `Error reading fd 8` while they are there. Skipped while pacman runs.
- **AUR build cache** — cleans `~/.cache/yay` or `~/.cache/paru` when an AUR helper is present.
- **Unneeded AUR deps** — removes orphaned AUR dependencies via `yay -Yc` / `paru -c`.

The closing summary counts what each step removed (packages, cache files, stale dirs) and how much space the caches gave back.

Requires `pacman`, `paccache`, `find`, `pgrep`, optionally `yay` or `paru`. One confirmation guards everything; pacman/paccache steps need `sudo`. No AUR helper: AUR steps skip with a notice. The build cache is emptied directly (`rm -rf ~/.cache/yay/*`), not via `yay -Sc`, which also runs `pacman -Sc` and would break the keep-3 policy.

```sh
repository-clean
```

---

## git-maintenance

Safe git maintenance for every repository under a directory tree. Never touches the working tree: no `git clean`, no reflog expiry, no `--prune=now`, and never deletes branches, tags, stashes or remotes.

Each repo reports size before/after, loose→packed object counts, pruned remote refs and the `fsck` result. The summary totals repos optimized/skipped (scanned/skipped in dry-run), space reclaimed and refs pruned, then lists every tracked+ignored file (as `repo/path`) and any repo with `fsck` errors.

Tracked files listed in `.gitignore` are usually a mistake. `-u` untracks them with `git rm --cached`: file kept on disk, changes staged, not committed. Submodule gitlinks are skipped. `-n` reports them without untracking.

```sh
git-maintenance                 # optimize all repos under /home/bubba/Projects
git-maintenance /some/dir       # optimize repos under a specific directory
git-maintenance -b /some/dir    # same, via flag
git-maintenance -u              # also untrack reported tracked+ignored files
git-maintenance -n              # dry run: report stats, change nothing
git-maintenance -a              # aggressive: --aggressive --prune=now (much slower)
```

---

## big-files

Lists files above a size threshold (MB), grouped by enclosing `.git` project, largest first, with a green-to-red colour ramp. Hidden and ignored files included. Requires `fd` and `stat`.

```sh
big-files                # scan the current directory, over 5 MB
big-files /some/dir      # scan a specific directory
big-files 50             # files over 50 MB
big-files 0.5            # decimals are fine
big-files -s 50          # same, via flag
big-files /some/dir 50   # both
```

---

## install-apps

Installs a fixed set of packages: repo apps via `pacman`, AUR apps via `yay` (or `paru` when yay is absent). The repo step is a full `pacman -Syu`, so it never partial-upgrades. Edit the `REPO_APPS` / `AUR_APPS` arrays to change the set.

```sh
./src/install-apps.sh
```

---

## lact-gaming

LACT "Gaming" profile hook: monitor refresh switch plus parking background tray apps.

- `on` — records the active refresh mode, stops any running `cliptoo` and KopiaUI (`/opt/KopiaUI/kopia-ui`) instances (recording which), then switches `DP-1` to 240Hz.
- `off` — restores the recorded mode (120Hz fallback if none was captured), then restarts only the apps that were running at activation. State lives in `~/.local/state/lact-gaming/state`.

Idempotent: an existing state file (a previous `off` never fired) is kept rather than overwritten, so a later `off` still restores the right mode and apps.

```sh
./src/lact-gaming.sh on     # gaming profile activated
./src/lact-gaming.sh off    # gaming profile deactivated
```

Point the LACT Gaming profile hooks at this script:

```yaml
hooks:
  activated: /home/bubba/Projects/_scripts/src/lact-gaming.sh on
  deactivated: /home/bubba/Projects/_scripts/src/lact-gaming.sh off
```

Requires `kscreen-doctor`, `loginctl`, `runuser` and `setsid` (util-Linux), plus `pgrep`/`pkill` (procps-ng) and `awk`.

---

## opencode-maintenance

Maintenance for the OpenCode v2 database:

- Backs up first: `sqlite3 .backup` piped through `gzip` to `~/Downloads/opencode-db-<date>.db.gz`, keeping the 3 newest.
- Removes rows for project directories that no longer exist (they surface as "Failed to send prompt / Unable to retrieve session").
- Drops the frozen legacy `session`/`message`/`part` rows migrated to `session_v2`/`session_message`, but only rows also present in `session_v2`, so no history is lost.
- Optionally prunes sessions with no activity for a number of days.
- Deletes `snapshot/<project-id>/` git dirs with no DB row (revert snapshots; `global` kept).
- Rotates `~/.local/share/opencode/log/opencode.log` and its own transcript, `~/.local/state/opencode/maintenance/maintenance.log`, past `LOG_MAX_MB`.
- Runs `VACUUM`.
- Prints a `summary` line: rows pruned, DB size delta / reusable pages, snapshot and log bytes freed.

From a terminal it prompts for backup, dead-path grace, session age and VACUUM. With no tty (cron, systemd `--user`) it runs unattended: VACUUM on, backup off, no age prune. Pinning a setting with its env var skips that prompt.

A path must stay missing for `DEAD_GRACE_DAYS` (default 7) before its sessions are pruned, only paths under `ROOTS` (default `~/Projects`) count, and DB writes (backup and `VACUUM`, which needs an exclusive lock) are skipped while OpenCode runs — snapshot and log cleanup still run. Output goes to `~/.local/state/opencode/maintenance/maintenance.log` and the terminal.

```sh
opencode-maintenance                 # interactive: 4 questions, Enter = defaults
DRY_RUN=1 opencode-maintenance       # report the full plan, change nothing, no prompts
BACKUP=1 SESSION_MAX_AGE_DAYS=60 ASSUME_YES=1 DO_VACUUM=1 opencode-maintenance   # unattended, with backup
```

All are environment variables; none are command-line flags.

| Variable | Default | Effect |
| --- | --- | --- |
| `BACKUP` | prompt (`Y`); `0` when unattended, `1` under `DRY_RUN` | Gzipped DB backup before any write. A failed backup aborts the run. |
| `BACKUP_DIR` | `~/Downloads` | Where `opencode-db-<date>.db.gz` goes. |
| `BACKUP_KEEP` | `3` | Newest backups kept; older ones deleted after each successful backup. |
| `DEAD_GRACE_DAYS` | prompt (`7`) | Days a missing project path must stay missing before its rows are pruned. Also the minimum age of an orphan snapshot dir. |
| `SESSION_MAX_AGE_DAYS` | prompt (`60`); `0` when unattended, `60` under `DRY_RUN` | Prune sessions inactive this many days. `0` disables. Without a tty it also needs `ASSUME_YES=1`, else the prune is skipped. |
| `ASSUME_YES` | `0` | `1` deletes ripe sessions without the `[y/N]` confirmation. |
| `DO_VACUUM` | prompt (`Y`) / `1` | Run `VACUUM` at the end. Needs OpenCode closed; also compacts pages freed by earlier runs. |
| `LOG_MAX_MB` | `50` | Rotate `opencode.log` and `maintenance.log` above this size. `0` disables. |
| `LOG_KEEP` | `3` | `.gz` archives kept per log. |
| `ROOTS` | `$HOME/Projects` | Space-separated allowlist of path prefixes; sessions outside it are never pruned. Quote multiple: `ROOTS="$HOME/Projects /mnt/data/src"`. |
| `SNAP_DIR` | `$OC_DIR/snapshot` | Revert-snapshot store; project dirs without a DB row are deleted once older than `DEAD_GRACE_DAYS`. |
| `OC_DIR` | `~/.local/share/opencode` | Base data directory; `OC_DB` and `OC_LOG` default inside it. |
| `OC_DB`, `OC_LOG` | `$OC_DIR/opencode.db`, `$OC_DIR/log/opencode.log` | Override the DB or log path. |
| `OC_STATE` | `~/.local/state/opencode` | Parent of `maintenance/` (lock, dead-path state, transcript). |
| `DRY_RUN` | `0` | `1` logs every action as `DRY RUN - would ...`, skips all prompts, and changes no DB, snapshot or log state; the transcript is still appended. |

---

## last-installed

Colourized tail of `/var/log/pacman.log`. Actions are colour-coded and labelled `major`, `minor`, `patch`, `build`, `pkgrel` or `epoch`; packages absent from every sync database (AUR/foreign) get a pink `*AUR` marker. Requires `awk` and `pacman`.

```sh
last-installed         # last 50 transactions
last-installed 100     # last 100
```

---

## long-files

Reports text files over 400 lines (or a custom limit), grouped by enclosing `.git` project, largest first. Files outside any `.git` project group by top-level directory. Binary detection is by content, so no extension whitelist. Hidden files and `.gitignore` matches are skipped (unlike `big-files`). Requires `fd`, `grep`, `xargs` and `wc`.

```sh
long-files                # scan the current directory, limit 400 lines
long-files /some/dir      # scan a specific directory
long-files 800            # custom line limit
long-files /some/dir 800  # both
```

---

## music

FLAC library tooling under `src/music/`. `flac-conversion.py` caps a library at 16-bit / 48 kHz into a separate tree; see `src/music/README.md` for its `scan` / `convert` / `verify` / `move` workflow, defaults and caveats.

`artists-with-flac.sh` prints each artist directory under `/mnt/data/Music` holding at least one FLAC.

`music-48k-move.sh` replaces library files with the converted copies from `/mnt/data/Music-48k`, matching by relative path only. Dry run by default; `--apply` moves. It also reports per-directory files present on only one side.

```sh
./src/music/artists-with-flac.sh
./src/music/music-48k-move.sh           # dry run: list what would be replaced
./src/music/music-48k-move.sh --apply   # replace matching library files
```

Both shell scripts hardcode their paths: `/mnt/data/Music` for both, plus `/mnt/data/Music-48k` for the move script.

---

## old-files

Lists files not touched for 90 days (or a custom age), one `date`, `age`, `path` line each, sorted by path. Date and age ramp from pale red at 6 months to full red at 5 years and beyond; younger entries stay uncoloured. Prunes `.git`, `.cache`, `.bun`, `node_modules`, `target` and `.venv`, stays on one filesystem, and stops four levels below the base (`find -maxdepth 4`).

With `-d` it lists directories instead of files, reporting only those with no content touched since the cutoff; the date shown is the newest descendant's, and deeper matches collapse into their newest ancestor, so a dormant tree is reported once rather than per directory.

```sh
old-files                # scan the current directory, 90 days
old-files /some/dir      # scan a specific directory
old-files 30             # 30 days
old-files /some/dir 30   # both
old-files -d             # directories rather than files
```

---

## health-check

Read-only report of potential system-wide issues. Signal-only: a section prints only when a check finds something, known-benign log/package noise is filtered, and the exit code is non-zero when any issue group is found.

- **Failed units** — failed system and user systemd units.
- **Packaging** — `pacman -Dk` database errors, `pacman -Qkq` missing package files (expected runtime paths filtered), `pacman -Qtdq` true orphans, and `paccheck --md5sum --files --quiet` when `pacutils` is installed.
- **Logs** — priority-`err` journal lines for this boot, kernel-only `err` lines, and `dmesg --level=err,warn`.
- **Btrfs** — `device stats` error counters and `scrub status -R` per detected filesystem.
- **SMART** — health verdict plus critical attributes per detected disk.

Privileged checks (Btrfs, SMART, `dmesg`) run through `sudo` when available and count as skipped otherwise, so the report still runs unprivileged.

```sh
./src/health-check.sh              # full report (only findings shown)
./src/health-check.sh -q           # skip the paccheck md5sum sweep
./src/health-check.sh -v           # verbose: raw output, no noise filter
./src/health-check.sh --no-sudo    # skip privileged checks (no effect as root)
```

Suppressed patterns are extended regexes: built-in defaults plus any lines in `~/.config/health-check/ignore` (override with `HEALTH_CHECK_IGNORE`). Use `-v` to see unfiltered output before adding a pattern. An invalid regex aborts the run with exit 2 and names the offending line, instead of filtering every finding away.

Requires `systemctl`, `journalctl`, `pacman`. Optional: `paccheck` (pacutils), `btrfs-progs`, `smartmontools`. Btrfs mounts and block devices are auto-detected; override with `BTRFS_MOUNTS` / `SMART_DEVICES`. `MAX_LINES` (default 25) caps lines shown per findings list.
