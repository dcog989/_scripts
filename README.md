# scripts

A collection of scripts for maintaining an Arch-based (CachyOS) system and its git repositories. Each script is self-contained and can be sourced or run directly.

## Contents

| Script | Type | Purpose |
| --- | --- | --- |
| `src/repoclean.fish` | fish function | List then clean pacman/AUR package leftovers (orphans, caches, unneeded deps). |
| `src/git-maintenance.fish` | fish function | Safely optimize every git repo under a directory tree. |
| `src/git-ignore-tidy.fish` | fish function | Report and untrack files that are both tracked and ignored. |
| `src/update-opencode.fish` | fish function | Update the opencode CLI and desktop AppImage. |
| `src/install-apps.sh` | bash script | Install a fixed set of repo and AUR packages. |
| `src/refresh.sh` | bash script | Switch the DP-1 monitor refresh rate (LACT profile hook). |

## Install

Fish functions: source them, or drop them into your fish functions directory.

```sh
source /path/to/src/repoclean.fish
# or
cp src/*.fish ~/.config/fish/functions/
```

Shell scripts: make them executable and run them directly.

```sh
chmod +x src/*.sh
./src/install-apps.sh
```

Most scripts assume the developer environment described in `AGENTS.md`
(pacman/paccache, `yay`, `git`, `jq`, `curl`).

---

## repoclean

Lists and cleans pacman/AUR package leftovers on Arch-based systems. Prints a
report, asks for confirmation, then runs the cleanup steps.

Cleans:

- **Orphans** — packages installed as dependencies that are no longer required (`pacman -Qdtq`).
- **Package cache** — prunes `/var/cache/pacman/pkg` keeping the 3 most recent versions, and drops cached packages for uninstalled packages (`paccache`).
- **AUR build cache** — reports and cleans `~/.cache/yay` or `~/.cache/paru` when an AUR helper is present.
- **Unneeded AUR deps** — removes orphaned AUR dependencies via `yay -Yc` / `paru -c`.

Requires `pacman`, `paccache`, and optionally `yay` or `paru`. Destructive
operations run only after confirmation; pacman/paccache steps require `sudo`.
If no AUR helper is found, AUR-specific steps are skipped with a notice.

```sh
repoclean
```

---

## git-maintenance

Safe git maintenance for every repository under a directory tree. By default it
never touches the working tree: no `git clean`, no reflog expiry, no
`--prune=now`, and never deletes branches, tags, stashes or remotes.

Each repo reports size before/after, loose→packed object counts, pruned remote
refs, and the `fsck` result.

```sh
git-maintenance                 # optimize all repos under /home/bubba/Projects
git-maintenance /some/dir       # optimize repos under a specific directory
git-maintenance -b /some/dir    # same, via flag
git-maintenance -n              # dry run: report stats, change nothing
git-maintenance -a              # aggressive: --aggressive --prune=now (much slower)
```

---

## git-ignore-tidy

Reports files that are both tracked and ignored (a tracked file listed in
`.gitignore` is usually a mistake). Removal uses `git rm --cached`, keeping the
file on disk; changes are staged, not committed. Submodule gitlinks are skipped.

```sh
git-ignore-tidy                 # scan all repos under /home/bubba/Projects
git-ignore-tidy /some/dir       # scan a specific directory
git-ignore-tidy -b /some/dir    # same, via flag
git-ignore-tidy -n              # report only, never prompt or remove
git-ignore-tidy -y              # untrack all matches without prompting
```

---

## update-opencode

Updates the opencode CLI and desktop AppImage from the latest GitHub release.
Skips if already current, stops running opencode processes before replacing
binaries in `~/.local/bin`.

```sh
update-opencode
```

Requires `curl` and `jq`.

---

## install-apps

Installs a fixed set of packages: repo apps via `pacman` (CachyOS v3 / Arch)
and AUR apps via `yay`. Edit the `REPO_APPS` / `AUR_APPS` arrays to change the set.

```sh
./src/install-apps.sh
```

---

## refresh

Switches the `DP-1` monitor refresh rate between 240Hz and 120Hz. Designed as a
LACT profile hook: run with `on` when a game profile activates and `off` when it
deactivates. When run as root (`lactd`), it picks up the desktop session
environment automatically.

```sh
./src/refresh.sh 240   # switch to 240Hz
./src/refresh.sh 120   # switch to 120Hz
```

Requires `kscreen-doctor`.
