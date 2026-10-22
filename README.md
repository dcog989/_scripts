# scripts

A collection of scripts for maintaining Arch/CachyOS, pacman/AUR/git repositories, etc.

## Contents

| Script | Type | Purpose |
| --- | --- | --- |
| `src/big-files.fish`            | fish function | List files above a size threshold (default 5 MB), largest first. |
| `src/git-maintenance.fish`      | fish function | Safely optimize every git repo under a directory tree and untrack tracked+ignored files. |
| `src/health-check.sh`           | shell script  | Read-only report of system-wide issues (units, packages, logs, Btrfs, SMART). |
| `src/install-apps.sh`           | shell script  | Install a fixed set of repo and AUR packages. |
| `src/lact-gaming.sh`            | shell script  | LACT Gaming hook: switch refresh rate and park/restore cliptoo and KopiaUI. |
| `src/last-installed.fish`       | fish function | Recent pacman transactions, colourized, with changed version parts highlighted. |
| `src/long-files.fish`           | fish function | Report text files over 400 lines, grouped by project. |
| `src/music/flac-conversion.py`  | Python script | Cap hi-res FLAC at 16-bit / 48 kHz into a separate target tree. |
| `src/opencode-maintenance.sh`   | shell script  | Prune OpenCode DB rows and snapshots for dead projects, and rotate its log. |
| `src/opencode-update.fish`      | fish function | Update the opencode CLI and desktop AppImage. |
| `src/repository-clean.fish`     | fish function | List then clean pacman/AUR package leftovers (orphans, caches, unneeded deps). |
| `src/stale.sh`                  | shell script  | List content not touched for 80 days. |

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

Lists and cleans pacman/AUR package leftovers on Arch-based systems. Prints a report, asks for confirmation, then runs the cleanup.

Cleans:

- **Orphans** — packages installed as dependencies that are no longer required (`pacman -Qdtq`).
- **Package cache** — prunes `/var/cache/pacman/pkg` with `paccache -k 3`, then clears it further via the AUR helper's `-Sc`. The report previews what those steps actually reclaim (cached versions beyond keep-3 plus every version of an uninstalled package).
- **Stale download dirs** — removes the `download-XXXXXX` temp dirs libalpm leaks into the package cache after an interrupted download. `pacman -Sc` fails with `Error reading fd 8` while they are there. Skipped while pacman is running.
- **AUR build cache** — reports and cleans `~/.cache/yay` or `~/.cache/paru` when an AUR helper is present.
- **Unneeded AUR deps** — removes orphaned AUR dependencies via `yay -Yc` / `paru -c`.

The closing summary counts what each step removed (packages, cache files, stale dirs) and how much space the pacman and AUR caches gave back.

Requires `pacman`, `paccache`, and optionally `yay` or `paru`. Destructive operations run only after confirmation; pacman/paccache steps require `sudo`. If no AUR helper is found, AUR-specific steps are skipped with a notice. The AUR cache step runs `yay -Sc` without `--noconfirm`, so yay and pacman ask before wiping the AUR build cache, before dropping cached packages and before removing unused sync repositories — answer them to control what goes.

```sh
repository-clean
```

---

## git-maintenance

Safe git maintenance for every repository under a directory tree. It never touches the working tree: no `git clean`, no reflog expiry, no `--prune=now`, and never deletes branches, tags, stashes or remotes.

Each repo reports size before/after, loose→packed object counts, pruned remote refs, and the `fsck` result. The closing summary totals repos optimized/skipped (scanned/skipped in dry-run), space reclaimed and remote refs pruned, then lists every tracked+ignored file (as `repo/path`) and any repo with `fsck` errors.

It also reports files that are both tracked and ignored (a tracked file listed in `.gitignore` is usually a mistake). With `-u` it untracks them: removal uses `git rm --cached`, keeping the file on disk and only stopping tracking; changes are staged, not committed. Submodule gitlinks are skipped. Under `-n` these files are reported but not untracked.

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

Lists files larger than a size threshold (in MB), grouped by enclosing `.git` project and sorted by size (largest first), with a green-to-red colour ramp. Hidden and ignored files are included.

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

Installs a fixed set of packages: repo apps via `pacman` and AUR apps via `yay` (or `paru` when yay is absent). Edit the `REPO_APPS` / `AUR_APPS` arrays to change the set.

```sh
./src/install-apps.sh
```

---

## lact-gaming

LACT "Gaming" profile hook combining the refresh switch with parking lightweight background tray apps.

- `on` — record the refresh mode that was active beforehand, stop any running `cliptoo` and KopiaUI (`/opt/KopiaUI/kopia-ui`) instances (recording which ones were running), then switch `DP-1` to 240Hz.
- `off` — restore the recorded refresh mode (falling back to 120Hz if none was captured), then restart only the apps that were running at activation. State lives in `~/.local/state/lact-gaming/state`.

Activation is idempotent: if the state file already exists (a previous `off` never fired), the recorded mode and apps are kept rather than overwritten, so a later `off` still restores them.

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

Requires `kscreen-doctor`, `loginctl`, and `runuser` (util-Linux).

---

## opencode-maintenance

Maintenance for OpenCode v2 database:

- Backs up the DB first: `sqlite3 .backup` piped through `gzip` to `~/Downloads/opencode-db-<date>.db.gz`, keeping the 3 newest.
- Removes SQLite rows for project directories that no longer exist (which otherwise surface as "Failed to send prompt / Unable to retrieve session").
- Drops the frozen legacy `session`/`message`/`part` rows that OpenCode migrated to `session_v2`/`session_message` (only rows also present in `session_v2`, so no history is lost).
- Optionally prunes sessions with no activity for a number of days.
- Deletes `snapshot/<project-id>/` git dirs for projects no longer in the DB (revert snapshots; `global` is kept).
- Rotates `~/.local/share/opencode/log/opencode.log` and its own run transcript, `~/.local/state/opencode/maintenance/maintenance.log`, past `LOG_MAX_MB`.
- Runs `VACUUM`.
- Prints a `summary` line with rows pruned, DB file size delta / reusable pages, snapshot and log bytes freed.

From a terminal it prompts for backup, dead-path grace, session age, VACUUM options. With no tty (cron, systemd `--user`) it runs unattended: VACUUM on, backup off, no age prune. Any setting can be pinned with its env var, which also skips that prompt.

A path must be missing for `DEAD_GRACE_DAYS` (default 7) before its sessions are pruned, only paths under `ROOTS` (default `~/Projects`) are considered, and DB writes (including the backup and `VACUUM`, which needs an exclusive lock) are skipped while OpenCode is running — snapshot and log cleanup still run. Output is appended to `~/.local/state/opencode/maintenance/maintenance.log` and echoed to the terminal.

```sh
opencode-maintenance                 # interactive: 4 questions, Enter = defaults
DRY_RUN=1 opencode-maintenance       # report the full plan, change nothing, no prompts
BACKUP=1 SESSION_MAX_AGE_DAYS=60 ASSUME_YES=1 DO_VACUUM=1 opencode-maintenance   # unattended, with backup
```

### Settings

All are environment variables; none are command-line flags. Setting one skips the matching prompt.

| Variable | Default | Effect |
| --- | --- | --- |
| `BACKUP` | prompt (`Y`); `0` when unattended, `1` under `DRY_RUN` | Gzipped DB backup before any write. A failed backup aborts the run. |
| `BACKUP_DIR` | `~/Downloads` | Where `opencode-db-<date>.db.gz` goes. |
| `BACKUP_KEEP` | `3` | Newest backups kept; older ones are deleted after each successful backup. |
| `DEAD_GRACE_DAYS` | prompt (`7`) | Days a missing project path must stay missing before its rows are pruned. Also the minimum age of an orphan snapshot dir. |
| `SESSION_MAX_AGE_DAYS` | prompt (`60`); `0` when unattended, `60` under `DRY_RUN` | Prune sessions with no activity for this many days. `0` disables. Without a tty it also needs `ASSUME_YES=1`, otherwise the prune is skipped. |
| `ASSUME_YES` | `0` | `1` deletes ripe sessions without the `[y/N]` confirmation. |
| `DO_VACUUM` | prompt (`Y`) / `1` | Run `VACUUM` at the end. Needs OpenCode closed; compacts pages freed by earlier runs too. |
| `LOG_MAX_MB` | `50` | Rotate `opencode.log` and `maintenance.log` once above this size. `0` disables rotation. |
| `LOG_KEEP` | `3` | Number of `.gz` archives kept per log. |
| `ROOTS` | `$HOME/Projects` | Space-separated allowlist of path prefixes; sessions outside it are never pruned. Quote multiple: `ROOTS="$HOME/Projects /mnt/data/src"`. |
| `SNAP_DIR` | `$OC_DIR/snapshot` | Revert-snapshot store; project dirs without a DB row are deleted once older than `DEAD_GRACE_DAYS`. |
| `OC_DIR` | `~/.local/share/opencode` | Base data directory; `OC_DB` and `OC_LOG` default inside it. |
| `OC_DB`, `OC_LOG` | `$OC_DIR/opencode.db`, `$OC_DIR/log/opencode.log` | Override the DB or log path. |
| `OC_STATE` | `~/.local/state/opencode` | Parent of `maintenance/` (lock, dead-path state, transcript). |
| `DRY_RUN` | `0` | `1` logs every action as `DRY RUN - would ...`, skips all prompts, and makes no DB, snapshot or log-rotation changes; the run transcript is still appended. |

---

## opencode-update

Updates the opencode CLI and desktop AppImage from the latest GitHub release. Skips if already current, stops running opencode processes before replacing binaries in `~/.local/bin`.

```sh
opencode-update
```

Requires `curl` and `jq`.

---

## last-installed

Colourized tail of `/var/log/pacman.log`. Actions are colour-coded and labelled `major`, `minor`, `patch`, `build`, `pkgrel` or `epoch`. Requires `awk`.

```sh
last-installed         # last 50 transactions
last-installed 100     # last 100
```

---

## long-files

Reports text files exceeding 400 lines (or a custom limit), grouped by enclosing `.git` project and sorted by line count (largest first). Files outside any `.git` project are grouped by their top-level directory. Binary files are detected by content, so no extension whitelist is involved.

```sh
long-files                # scan the current directory, limit 400 lines
long-files /some/dir      # scan a specific directory
long-files 800            # custom line limit
long-files /some/dir 800  # both
```

---

## health-check

Read-only report of potential system-wide issues. Signal-only: it prints a section only when a check finds something, filters known-benign log/package noise, and exits non-zero when any issue group is found.

- **Failed units** — failed system and user systemd units.
- **Packaging** — `pacman -Dk` database errors, `pacman -Qkq` missing package files (expected runtime paths filtered), `pacman -Qtdq` true orphans, and `paccheck --md5sum --files --quiet` when `pacutils` is installed.
- **Logs** — priority-`err` journal lines for the current boot, kernel-only `err` lines, and `dmesg --level=err,warn`.
- **Btrfs** — `device stats` error counters and `scrub status -R` per detected filesystem.
- **SMART** — health verdict plus critical attributes per detected disk.

Privileged checks (Btrfs, SMART, `dmesg`) run through `sudo` when available and are counted as skipped otherwise, so the report still runs unprivileged.

```sh
./src/health-check.sh              # full report (only findings shown)
./src/health-check.sh -q           # skip the paccheck md5sum sweep
./src/health-check.sh -v           # verbose: raw output, no noise filter
./src/health-check.sh --no-sudo    # skip privileged checks (no effect as root)
```

Suppressed patterns are extended regexes: built-in defaults plus any lines in `~/.config/health-check/ignore` (override with `HEALTH_CHECK_IGNORE`). Run with `-v` to see the unfiltered output before adding a pattern.

Requires `systemctl`, `journalctl`, `pacman`. Optional: `paccheck` (pacutils), `btrfs-progs`, `smartmontools`. Btrfs mounts and block devices are auto-detected; override with `BTRFS_MOUNTS` / `SMART_DEVICES`. `MAX_LINES` (default 25) caps lines shown per findings list.
