# scripts

A collection of scripts for maintaining an Arch-based (CachyOS) system and its git repositories. Each script is self-contained and can be sourced or run directly.

## Contents

| Script | Type | Purpose |
| --- | --- | --- |
| `src/repository-clean.fish` | fish function | List then clean pacman/AUR package leftovers (orphans, caches, unneeded deps). |
| `src/git-maintenance.fish` | fish function | Safely optimize every git repo under a directory tree. |
| `src/git-ignore-tidy.fish` | fish function | Report and untrack files that are both tracked and ignored. |
| `src/big-files.fish` | fish function | Report source files over 400 lines, grouped by project. |
| `src/opencode-update.fish` | fish function | Update the opencode CLI and desktop AppImage. |
| `src/install-apps.sh` | bash script | Install a fixed set of repo and AUR packages. |
| `src/monitor-refresh.sh` | bash script | Switch the DP-1 monitor refresh rate (LACT profile hook). |
| `src/lact-gaming.sh` | bash script | LACT Gaming hook: switch refresh rate and park/restore cliptoo and KopiaUI. |
| `src/opencode-maintenance.sh` | bash script | Prune OpenCode DB rows and snapshots for dead projects, and rotate its log. |

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
- **Package cache** — prunes `/var/cache/pacman/pkg` with `paccache`, then clears it further via the AUR helper's `-Sc`. The report previews what that actually reclaims (old versions at keep-1 plus uninstalled packages).
- **AUR build cache** — reports and cleans `~/.cache/yay` or `~/.cache/paru` when an AUR helper is present.
- **Unneeded AUR deps** — removes orphaned AUR dependencies via `yay -Yc` / `paru -c`.

Requires `pacman`, `paccache`, and optionally `yay` or `paru`. Destructive operations run only after confirmation; pacman/paccache steps require `sudo`. If no AUR helper is found, AUR-specific steps are skipped with a notice.

```sh
repository-clean
```

---

## git-maintenance

Safe git maintenance for every repository under a directory tree. By default it never touches the working tree: no `git clean`, no reflog expiry, no `--prune=now`, and never deletes branches, tags, stashes or remotes.

Each repo reports size before/after, loose→packed object counts, pruned remote refs, and the `fsck` result.

```sh
git-maintenance                 # optimize all repos under /home/bubba/Projects
git-maintenance /some/dir       # optimize repos under a specific directory
git-maintenance -b /some/dir    # same, via flag
git-maintenance -n              # dry run: report stats, change nothing
git-maintenance -a              # aggressive: --aggressive --prune=now (much slower)
```

---

## git-ignore-tidy

Reports files that are both tracked and ignored (a tracked file listed in `.gitignore` is usually a mistake). Removal uses `git rm --cached`, keeping the file on disk; changes are staged, not committed. Submodule gitlinks are skipped.

```sh
git-ignore-tidy                 # scan all repos under /home/bubba/Projects
git-ignore-tidy /some/dir       # scan a specific directory
git-ignore-tidy -b /some/dir    # same, via flag
git-ignore-tidy -n              # report only, never prompt or remove
git-ignore-tidy -y              # untrack all matches without prompting
```

---

## big-files

Reports source files exceeding 400 lines, grouped by enclosing project and sorted by line count (largest first). A directory counts as a project root when it contains a `.git` marker; files outside any project are grouped by their top-level directory.

```sh
big-files                # scan the current directory
big-files /some/dir      # scan a specific directory
```

---

## opencode-update

Updates the opencode CLI and desktop AppImage from the latest GitHub release. Skips if already current, stops running opencode processes before replacing binaries in `~/.local/bin`.

```sh
opencode-update
```

Requires `curl` and `jq`.

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

- `on` — switch `DP-1` to 240Hz, record the refresh mode that was active beforehand, then stop any running `cliptoo` and KopiaUI (`/opt/KopiaUI/kopia-ui`) instances, recording which ones were running.
- `off` — restore the recorded refresh mode (falling back to 120Hz if none was captured), then restart only the apps that were running at activation. State lives in `~/.local/state/lact-gaming/state`.

Activation is idempotent: if the state file already exists (a previous `off` never fired), the recorded mode and apps are kept rather than overwritten, so a later `off` still restores them. The desktop refresh is managed directly with `kscreen-doctor`.

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
- Deletes `snapshot/<project-id>/` git dirs for projects no longer in the DB (revert snapshots; `global` is kept).
- Rotates `~/.local/share/opencode/log/opencode.log`.

A path must be missing for `DEAD_GRACE_DAYS` (default 7) before its sessions are pruned, only paths under `ROOTS` (default `~/Projects`) are considered, and DB writes are skipped while OpenCode is running (snapshot/log cleanup still runs). Output is appended to `~/.local/state/opencode/maint/maint.log` and echoed to the terminal. Intended to run from a systemd user timer or cron.

```sh
./src/opencode-maintenance.sh                 # normal run
DRY_RUN=1 ./src/opencode-maintenance.sh       # report what would be pruned, change nothing
DEAD_GRACE_DAYS=0 ./src/opencode-maintenance.sh
```

Tunables: `DEAD_GRACE_DAYS`, `LOG_MAX_MB`, `LOG_KEEP`, `DO_VACUUM`, `ROOTS`, `SNAP_DIR`.
