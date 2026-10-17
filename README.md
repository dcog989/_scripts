# scripts

A collection of scripts for maintaining an Arch-based (CachyOS) system and its git repositories. Each script is self-contained and can be sourced or run directly.

## Contents

| Script | Type | Purpose |
| --- | --- | --- |
| `src/repository-clean.fish` | fish function | List then clean pacman/AUR package leftovers (orphans, caches, unneeded deps). |
| `src/git-maintenance.fish` | fish function | Safely optimize every git repo under a directory tree and untrack tracked+ignored files. |
| `src/big-files.fish` | fish function | Report source files over 400 lines, grouped by project. |
| `src/opencode-update.fish` | fish function | Update the opencode CLI and desktop AppImage. |
| `src/install-apps.sh` | bash script | Install a fixed set of repo and AUR packages. |
| `src/monitor-refresh.sh` | bash script | Switch the DP-1 monitor refresh rate (LACT profile hook). |
| `src/lact-gaming.sh` | bash script | LACT Gaming hook: switch refresh rate and park/restore cliptoo and KopiaUI. |
| `src/opencode-maintenance.sh` | bash script | Prune OpenCode DB rows and snapshots for dead projects, and rotate its log. |
| `src/health-check.sh` | bash script | Read-only report of system-wide issues (units, packages, logs, Btrfs, SMART). |

## Install

Fish functions: source them directly, or symlink them into your fish functions directory so repo edits take effect immediately.

```sh
source /path/to/src/repository-clean.fish
# or
ln -sf /path/to/src/*.fish ~/.config/fish/functions/
```

Shell scripts: mark them executable and symlink them onto your `PATH`.

```sh
chmod +x /path/to/src/*.sh
ln -sf /path/to/src/*.sh ~/.local/bin/
```

Most scripts assume the developer environment described in `AGENTS.md` (pacman/paccache, `yay`, `git`, `jq`, `curl`).

---

## repository-clean

Lists and cleans pacman/AUR package leftovers on Arch-based systems. Prints a report, asks for confirmation, then runs the cleanup steps.

Cleans:

- **Orphans** — packages installed as dependencies that are no longer required (`pacman -Qdtq`).
- **Package cache** — prunes `/var/cache/pacman/pkg` with `paccache -k 3`, then clears it further via the AUR helper's `-Sc`. The report previews what those steps actually reclaim (cached versions beyond keep-3 plus every version of an uninstalled package).
- **AUR build cache** — reports and cleans `~/.cache/yay` or `~/.cache/paru` when an AUR helper is present.
- **Unneeded AUR deps** — removes orphaned AUR dependencies via `yay -Yc` / `paru -c`.

Requires `pacman`, `paccache`, and optionally `yay` or `paru`. Destructive operations run only after confirmation; pacman/paccache steps require `sudo`. If no AUR helper is found, AUR-specific steps are skipped with a notice.

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

Reports source files exceeding 400 lines, grouped by enclosing project and sorted by line count (largest first). A directory counts as a project root when it contains a `.git` marker; files outside any project are grouped by their top-level directory.

```sh
big-files                # scan the current directory
big-files /some/dir      # scan a specific directory
```

---

## install-apps

Installs a fixed set of packages: repo apps via `pacman` (CachyOS v3 / Arch) and AUR apps via `yay`. Edit the `REPO_APPS` / `AUR_APPS` arrays to change the set.

```sh
./src/install-apps.sh
```

---

## monitor-refresh

Switches the `DP-1` monitor refresh rate between 240Hz and 120Hz. With no argument it prints the current refresh rate and usage. Designed as a LACT profile hook: run with `240` when a game profile activates and `120` when it deactivates. When run as root (`lactd`), it picks up the desktop session environment automatically.

```sh
./src/monitor-refresh.sh        # print the current refresh rate and usage
./src/monitor-refresh.sh 240    # switch to 240Hz
./src/monitor-refresh.sh 120    # switch to 120Hz
```

Requires `kscreen-doctor`.

---

## lact-gaming

LACT "Gaming" profile hook combining the refresh switch with parking lightweight background tray apps.

- `on` — record the refresh mode that was active beforehand, stop any running `cliptoo` and KopiaUI (`/opt/KopiaUI/kopia-ui`) instances (recording which ones were running), then switch `DP-1` to 240Hz. Stopping apps before the mode switch matters: a modeset under a live Chromium tears down its GPU process.
- `off` — restore the recorded refresh mode (falling back to 120Hz if none was captured), then restart only the apps that were running at activation. State lives in `~/.local/state/lact-gaming/state`.

Activation is idempotent: if the state file already exists (a previous `off` never fired), the recorded mode and apps are kept rather than overwritten, so a later `off` still restores them. The desktop refresh is managed directly with `kscreen-doctor`. Restored apps are relaunched with the full desktop session environment (read from a running Plasma process), so toolkits load the correct KDE theme.

Designed to run as root from `lactd`; like `monitor-refresh.sh` it enters the session user's Wayland/X11 environment. Stop is graceful (`SIGTERM`, then `SIGKILL` after ~5s).

```sh
./src/lact-gaming.sh on     # gaming profile activated
./src/lact-gaming.sh off    # gaming profile deactivated
```

Point the LACT Gaming profile hooks at this script instead of `monitor-refresh.sh`:

```yaml
hooks:
  activated: /home/bubba/Projects/_scripts/src/lact-gaming.sh on
  deactivated: /home/bubba/Projects/_scripts/src/lact-gaming.sh off
```

Requires `kscreen-doctor`, `loginctl`, and `runuser` (util-Linux).

---

## opencode-maintenance

Periodic maintenance for OpenCode:

- Removes SQLite rows for project directories that no longer exist (which otherwise surface as "Failed to send prompt / Unable to retrieve session").
- Backs up the DB first: `sqlite3 .backup` piped through `gzip` to `~/Downloads/opencode-db-<date>.db.gz`, keeping the 3 newest. A failed backup aborts the run before anything is written.
- Drops the frozen legacy `session`/`message`/`part` rows that OpenCode migrated to `session_v2`/`session_message` (only rows also present in `session_v2`, so no history is lost).
- Optionally prunes sessions with no activity for a number of days.
- Deletes `snapshot/<project-id>/` git dirs for projects no longer in the DB (revert snapshots; `global` is kept).
- Rotates `~/.local/share/opencode/log/opencode.log` and its own run transcript, `~/.local/state/opencode/maintenance/maintenance.log`, past `LOG_MAX_MB`.
- Runs `VACUUM`.
- Prints a `summary` line with rows pruned, DB file size delta / reusable pages, snapshot and log bytes freed.

From a terminal it asks four questions up front — backup, dead-path grace, session age, VACUUM — and Enter takes the default. With no tty (cron, systemd `--user`) it runs unattended: VACUUM on, backup off, no age prune. Any setting can be pinned with its env var, which also skips that prompt.

A path must be missing for `DEAD_GRACE_DAYS` (default 7) before its sessions are pruned, only paths under `ROOTS` (default `~/Projects`) are considered, and DB writes (including the backup and `VACUUM`, which needs an exclusive lock) are skipped while OpenCode is running — snapshot and log cleanup still run. Output is appended to `~/.local/state/opencode/maintenance/maintenance.log` and echoed to the terminal. Intended to run from a systemd user timer or cron.

```sh
./src/opencode-maintenance.sh                 # interactive: 4 questions, Enter = defaults
DRY_RUN=1 ./src/opencode-maintenance.sh       # report the full plan, change nothing, no prompts
BACKUP=1 SESSION_MAX_AGE_DAYS=60 ASSUME_YES=1 ./src/opencode-maintenance.sh   # unattended, with backup
DEAD_GRACE_DAYS=0 DO_VACUUM=0 ./src/opencode-maintenance.sh
```

Settings: `BACKUP`, `BACKUP_DIR`, `BACKUP_KEEP`, `DEAD_GRACE_DAYS`, `SESSION_MAX_AGE_DAYS`, `ASSUME_YES`, `DO_VACUUM`, `LOG_MAX_MB`, `LOG_KEEP`, `ROOTS`, `SNAP_DIR`.

---

## opencode-update

Updates the opencode CLI and desktop AppImage from the latest GitHub release. Skips if already current, stops running opencode processes before replacing binaries in `~/.local/bin`.

```sh
opencode-update
```

Requires `curl` and `jq`.

---

## health-check

Read-only report of potential system-wide issues. Signal-only: it prints a section only when a check finds something, filters known-benign log/package noise, and exits non-zero when any issue group is found (handy for a timer/cron).

Checks:

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
