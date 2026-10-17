# Agent Directives

## Project

- Name: scripts
- Description: Collection of fish functions and shell scripts for maintaining an Arch-based (CachyOS) system and its git repositories.
- Tech: fish shell, bash, python3, pacman/paccache, yay (AUR), git, jq, curl, kscreen-doctor, ffmpeg, metaflac.

## Key Files

All scripts live in `src/`:

- `src/repository-clean.fish` — list then clean pacman/AUR package leftovers (orphans, caches, unneeded deps).
- `src/git-maintenance.fish` — safely optimize every git repo under a directory tree; report (and, with `-u`, untrack) tracked+ignored files.
- `src/big-files.fish` — report source files over 400 lines, grouped by project.
- `src/opencode-update.fish` — update the opencode CLI and desktop AppImage.
- `src/install-apps.sh` — install a fixed set of repo and AUR packages.
- `src/monitor-refresh.sh` — switch the DP-1 monitor refresh rate (LACT profile hook).
- `src/lact-gaming.sh` — LACT Gaming hook: switch refresh rate and park/restore tray apps.
- `src/opencode-maintenance.sh` — back up, prune (dead-path, legacy, age) and VACUUM the OpenCode DB; clean snapshot dirs; rotate its log.
- `src/health-check.sh` — read-only report of system-wide issues (units, packages, logs, Btrfs, SMART).
- `src/flac-conversion/flac-conversion.py` — scan a FLAC tree, transcode anything above 16-bit/48 kHz into a separate tree, verify the outputs.
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

### Verification

- After editing a fish file, run `fish -n src/<name>.fish` to confirm it parses.
- After editing a shell script, run `bash -n src/<name>.sh` to confirm it parses.
- Do not run destructive scripts in destructive mode during development unless the user asks.

## File System Access

- Allowed: <project root> and all contained directories + files; `/tmp/*`
- Read-Only: `.env*`, `.git/`, `.docs/Todo.md`
- Disallowed: everything not listed in 'Allowed' unless user grants permission.
- Require confirmation: adding/removing dependencies, any operation outside project root
- Do not delete files or make destructive changes without confirmation.

## Testing

- No automated tests. Validate via syntax checks (`fish -n`, `bash -n`) and manual dry-run review.
- Prefer scripts' built-in dry-run/`-n` paths when reviewing behavior.
- Do not create test files for trivial changes, or for behavior that is not reliably unit-testable in the test environment (e.g. UI layout/click mapping). Prefer no new files; only add a test when the logic is genuinely testable and worth guarding.

## Common Patterns

- Interactive/maintenance scripts: print a section header with `set_color`, dry-run report, then prompt, then execute guarded by `if test -n`.
- External dependency check: `command -q <tool>; and set var <tool>` pattern for optional tools (AUR helpers, etc.).
- Shared repo traversal: `find "$base" -name .git -prune` plus `git rev-parse --git-common-dir` to visit linked worktrees once.
- Skip repos with in-progress operations or locks (`index.lock`, `MERGE_HEAD`, rebase markers, …).
- Surface intentional defaults (keep-count, prune behavior) in dry-run output.

---

## General Guidelines

### Code Changes

- For non-trivial work, propose an approach and confirm before implementing.
- Keep modifications minimal and scoped; prefer incremental improvements over rewrites. Ask before architectural changes.
- Use explicit types and named constants (no magic numbers).
- Return explicit error types; do not suppress exceptions.
- Follow standard repository linting and formatting configs.
- Decompose files over 400 lines if they mix concerns.
- Use clear naming over comments; reserve comments for complex workarounds or non-obvious issues — why, not what.
- Never run git mutations (commit, push, reset, rebase, amend) unless explicitly instructed.
- Do not create documentation files unless explicitly requested.

### Author Environment

- CachyOS, KDE Plasma 6, Wayland, Btrfs.
- fish shell, Ghostty terminal, Fresh TUI editor, yay package manager, bun npm manager, Firefox, and Zed code editor.

### Testing

- Do not create test files for trivial changes, or for behavior that is not reliably unit-testable in the test environment (e.g. UI layout/click mapping). Prefer no new files; only add a test when the logic is genuinely testable and worth guarding.

### Definition of Done

- Logic fully implemented.
- Existing docs updated if public interfaces changed.
- When required by the `Verification` rules, run the corresponding `Workflow` command.

### Commit Messages

- On completion of an update or fix, print a conventional commit message in a fenced code block.
- Add a body only when the "why" isn't obvious.
- Do not wrap lines. One physical line per paragraph however long it gets. Never hard-wrap the subject or the body.

### Communication Style

- Fixes and instructions: numbered steps, one action each, exact command/path/code. No prose paragraphs or recap.
- Questions and explanations: direct prose, only the reasoning needed. No tables unless asked.
- No preamble, restating, hedging, disclaimers, meta-commentary, emotional framing, or closing offers; end when done unless a real decision is needed.
- Ask when requirements are ambiguous; put risks and edge cases in one final line.
