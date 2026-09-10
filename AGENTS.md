# Agent Directives

## Project

- Name: scripts
- Description: Collection of fish functions and shell scripts for maintaining an Arch-based (CachyOS) system and its git repositories.
- Tech: fish shell, bash, pacman/paccache, yay/paru (AUR), git, jq, curl, kscreen-doctor.

## Key Files

All scripts live in `src/`:

- `src/repoclean.fish` — list then clean pacman/AUR package leftovers (orphans, caches, unneeded deps).
- `src/git-maintenance.fish` — safely optimize every git repo under a directory tree.
- `src/git-ignore-tidy.fish` — report and untrack files that are both tracked and ignored.
- `src/update-opencode.fish` — update the opencode CLI and desktop AppImage.
- `src/install-apps.sh` — install a fixed set of repo and AUR packages.
- `src/refresh.sh` — switch the DP-1 monitor refresh rate (LACT profile hook).
- `README.md` — usage and overview.

## Workflow

### Commands

- Install (fish): source `src/<name>.fish`, or copy to `~/.config/fish/functions/`.
- Install (shell): `chmod +x src/*.sh` and run directly.
- Dev: edit the script; reload fish config or re-source the file.
- Test: `fish -n src/<name>.fish` (fish syntax check) and `bash -n src/<name>.sh` (bash syntax check).
- Lint: none configured.
- Format: `fish_indent src/<name>.fish` for fish; keep shell scripts POSIX/bash-clean.
- Build: none.

### Script Form

The form follows purpose, not language preference:

- `.fish` (sourced function) — interactive commands run from the user's fish session (report, prompt, colored output). Choose fish because `string`, `math`, `argparse`, `set_color` and `read -P` are cleaner than bash equivalents, and sourcing makes the command available directly in the shell.
- `.sh` (standalone executable) — non-interactive system integration: daemon hooks, provisioning/installers, anything run under `sudo` or by another process. These must not depend on the user's interactive shell.

When adding a script, pick the form from this rule. Don't convert a working script for consistency alone; the boundary is intentional.

### Code Changes

- Keep modifications minimal and scoped; prefer incremental improvements over rewrites. Ask before architectural changes.
- New scripts go in `src/` and follow the existing header-comment style (purpose + usage).
- Use explicit variable names; avoid magic numbers (e.g. repoclean cache keep-count `3` is a documented constant).
- Return explicit error types; do not suppress errors. Guard external command failures (e.g. missing AUR helper).
- Follow repository `.editorconfig` (fish and shell files use 2-space indent).
- Run the matching syntax check after edits (see Verification).
- Self-documenting code via clear naming. Use comments only for complex workarounds — why, not what.
- Never run git mutations (commit, push, reset, rebase, amend) unless explicitly instructed.
- Do not create documentation files unless explicitly requested. Update `README.md` when adding a script.

### Verification

- After editing a fish file, run `fish -n src/<name>.fish` to confirm it parses.
- After editing a shell script, run `bash -n src/<name>.sh` to confirm it parses.
- Do not run destructive scripts in destructive mode during development unless the user asks.

## Dev Environment

- CachyOS, KDE Plasma 6, Wayland, Btrfs.
- fish shell, Ghostty terminal, Fresh TUI editor, yay package manager, bun npm manager, Firefox, and Zed code editor.
- All software is up to date as of today.

## File System Access

- Allowed: <project root> and all contained directories + files; `/tmp/*`
- Read-Only: `.env*`, `.git/`
- Disallowed: everything not listed in 'Allowed' unless user grants permission.
- Require confirmation: adding/removing dependencies, any operation outside project root
- Do not delete files or make destructive changes without confirmation.

## Testing

- No automated tests. Validate via syntax checks (`fish -n`, `bash -n`) and manual dry-run review.
- Prefer scripts' built-in dry-run/`-n` paths when reviewing behavior.
- Do not create test files for trivial changes.

## Common Patterns

- Interactive/maintenance scripts: print a section header with `set_color`, dry-run report, then prompt, then execute guarded by `if test -n`.
- External dependency check: `command -q <tool>; and set var <tool>` pattern for optional tools (AUR helpers, etc.).
- Shared repo traversal: `find "$base" -name .git -prune` plus `git rev-parse --git-common-dir` to visit linked worktrees once.
- Skip repos with in-progress operations or locks (`index.lock`, `MERGE_HEAD`, rebase markers, …).
- Surface intentional defaults (keep-count, prune behavior) in dry-run output.

## Communication Style

- Provide concise, actionable responses.
- Ask clarifying questions when requirements are ambiguous.
- Flag potential risks or edge cases proactively.
- Do not pretend to understand how the user feels.
- Never editorialise your answer. No "to be honest", "honestly", hedging, disclaimers, or meta-commentary — just answer.

## Definition of Done

- Logic fully implemented.
- `README.md` updated if public interfaces changed or a script was added/removed.
- Syntax checks pass for every changed script.
- On completion of an update or fix, print a concise conventional commit message in a fenced code block.
