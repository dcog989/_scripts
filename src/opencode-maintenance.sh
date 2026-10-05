#!/usr/bin/env bash
# opencode-maintenance.sh - periodic maintenance for OpenCode
#
# `DRY_RUN=1 bash /home/bubba/Projects/_scripts/src/opencode-maintenance.sh`
# `bash /home/bubba/Projects/_scripts/src/opencode-maintenance.sh`
#
#  1. Prune OpenCode SQLite rows whose project directory no longer exists
#     (prevents "Failed to send prompt / Unable to retrieve session").
#     A path must be missing for DEAD_GRACE_DAYS before it is pruned.
#  2. Delete snapshot/<project-id>/ git dirs for projects no longer in the DB.
#  3. Rotate/truncate opencode.log when it grows past LOG_MAX_MB.
#
# Safe from cron / systemd --user. All filesystem/DB writes are skipped while
# OpenCode is running.
#
# Tunables (env):
#   DEAD_GRACE_DAYS=7   days a path must stay missing before pruning
#   LOG_MAX_MB=50       rotate the log above this size (0 disables)
#   LOG_KEEP=3          number of .gz archives to keep
#   DO_VACUUM=0         set 1 to VACUUM after a prune (slow)
#   ROOTS=...           space-separated whitelist of path roots
#   SNAP_DIR=...        snapshot store (default $OC_DIR/snapshot)
set -euo pipefail

OC_DIR="${OC_DIR:-$HOME/.local/share/opencode}"
DB="${OC_DB:-$OC_DIR/opencode.db}"
LOG="${OC_LOG:-$OC_DIR/log/opencode.log}"
SNAP_DIR="${SNAP_DIR:-$OC_DIR/snapshot}"
STATE_DIR="${OC_STATE:-$HOME/.local/state/opencode}/maintenance"
STATE_FILE="$STATE_DIR/dead_paths.tsv"
MAINT_LOG="$STATE_DIR/maintenance.log"

DEAD_GRACE_DAYS="${DEAD_GRACE_DAYS:-7}"
LOG_MAX_MB="${LOG_MAX_MB:-50}"
LOG_KEEP="${LOG_KEEP:-3}"
DO_VACUUM="${DO_VACUUM:-0}"
DRY_RUN="${DRY_RUN:-0}"
ROOTS=(${ROOTS:-"$HOME/Projects"})

mkdir -p "$STATE_DIR"
exec > >(tee -a "$MAINT_LOG") 2>&1
log() { printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*"; }

# single instance
exec 9>"$STATE_DIR/.lock"
flock -n 9 || { log "another run in progress"; exit 0; }

oc_running() {
  pgrep -af 'opencode-desktop|ai\.opencode\.desktop|/bin/opencode( |$)|opencode serve' >/dev/null
}

under_roots() {
  local p="$1" r
  for r in "${ROOTS[@]}"; do
    case "$p" in "$r"|"$r"/*) return 0;; esac
  done
  return 1
}

# ------------------------------------------------------------------ log rotation
if [ "$LOG_MAX_MB" -gt 0 ] && [ -f "$LOG" ]; then
  size_mb=$(( $(stat -c %s "$LOG") / 1048576 ))
  if [ "$size_mb" -ge "$LOG_MAX_MB" ]; then
    if [ "$DRY_RUN" = "1" ]; then
      log "DRY RUN - would rotate log (${size_mb}MB >= ${LOG_MAX_MB}MB)"
    else
      i=$LOG_KEEP
      while [ "$i" -gt 1 ]; do
        [ -f "$LOG.$((i-1)).gz" ] && mv -f "$LOG.$((i-1)).gz" "$LOG.$i.gz"
        i=$((i-1))
      done
      cp -a "$LOG" "$LOG.1" && gzip -f "$LOG.1"
      : > "$LOG"                      # copytruncate: app keeps its fd
      log "rotated log (${size_mb}MB) -> $(basename "$LOG").1.gz"
    fi
  else
    log "log ${size_mb}MB < ${LOG_MAX_MB}MB"
  fi
fi

# ------------------------------------------------------------------ db prune
[ -f "$DB" ] || { log "no db at $DB"; exit 0; }
skip_db=0
if oc_running; then log "OpenCode running - skipping DB prune"; skip_db=1; fi

tmp=$(mktemp); ripe=$(mktemp); newstate=$(mktemp)
trap 'rm -f "$tmp" "$ripe" "$newstate"' EXIT

for pair in "session directory" "project worktree" "project_directory directory" "workspace directory"; do
  set -- $pair
  sqlite3 "$DB" "SELECT DISTINCT $2 FROM $1 WHERE $2 IS NOT NULL AND $2<>'';" |
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    under_roots "$d" || continue
    [ -e "$d" ] || printf '%s\n' "$d"
  done
done | sort -u > "$tmp"

now=$(date +%s)
: > "$newstate"
if [ -f "$STATE_FILE" ]; then
  while IFS=$'\t' read -r p first; do
    [ -n "$p" ] || continue
    grep -qxF "$p" "$tmp" && printf '%s\t%s\n' "$p" "$first" >> "$newstate"
  done < "$STATE_FILE"
fi
while IFS= read -r p; do
  [ -n "$p" ] || continue
  grep -qF "$(printf '%s\t' "$p")" "$newstate" || printf '%s\t%s\n' "$p" "$now" >> "$newstate"
done < "$tmp"
if [ "$DRY_RUN" = "1" ]; then
  log "DRY RUN - would record $(wc -l < "$newstate") dead paths"
else
  mv "$newstate" "$STATE_FILE"
fi

cutoff=$(( now - DEAD_GRACE_DAYS*86400 ))
if [ -f "$STATE_FILE" ]; then
  awk -F'\t' -v c="$cutoff" '$2 <= c {print $1}' "$STATE_FILE" | sort -u > "$ripe"
else
  : > "$ripe"
fi
log "dead candidates: $(wc -l < "$tmp"), ripe: $(wc -l < "$ripe") (grace ${DEAD_GRACE_DAYS}d)"

if [ "$skip_db" = 0 ] && [ -s "$ripe" ]; then
  if [ "$DRY_RUN" = "1" ]; then
    log "DRY RUN - would prune paths:"; sed 's/^/  /' "$ripe"
  else
    sqlite3 "$DB" "PRAGMA wal_checkpoint(TRUNCATE);"
    python3 - "$DB" "$ripe" "$DO_VACUUM" <<'PY'
import sqlite3, sys
db, listfile, vacuum = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
paths = [l.rstrip("\n") for l in open(listfile) if l.strip()]
if not paths:
    print("nothing ripe"); sys.exit(0)
q = ",".join("?" * len(paths))
con = sqlite3.connect(db)
con.execute("PRAGMA foreign_keys=ON")
con.execute("BEGIN")
def run(s): return con.execute(s, paths).rowcount
n1 = run(f"DELETE FROM session           WHERE directory IN ({q})")
n2 = run(f"DELETE FROM project_directory WHERE directory IN ({q})")
n3 = run(f"DELETE FROM workspace         WHERE directory IN ({q})")
n4 = run(f"""DELETE FROM project
             WHERE worktree IN ({q})
               AND id NOT IN (SELECT DISTINCT project_id FROM session)""")
con.commit()
con.execute("PRAGMA optimize")
if vacuum:
    con.execute("VACUUM")
print(f"deleted sessions={n1} project_directory={n2} workspace={n3} projects={n4}")
con.close()
PY
    awk -F'\t' -v r="$ripe" '
      NR==FNR { dead[$1]=1; next }
      !($1 in dead)' "$ripe" "$STATE_FILE" > "$STATE_FILE.new" && mv "$STATE_FILE.new" "$STATE_FILE"
    log "db prune complete"
  fi
fi

# ------------------------------------------------------------------ snapshots
# snapshot/<project-id>/<snapshot-id>/ are per-project git dirs backing revert.
# A project id is random, never reused, so dirs without a project row are dead.
if [ -d "$SNAP_DIR" ]; then
  projids=$(mktemp); orphans=$(mktemp)
  trap 'rm -f "$tmp" "$ripe" "$newstate" "$projids" "$orphans"' EXIT
  sqlite3 "$DB" "SELECT id FROM project;" | sort -u > "$projids"
  age=(); [ "$DEAD_GRACE_DAYS" -gt 0 ] && age=(-mtime +"$DEAD_GRACE_DAYS")
  find "$SNAP_DIR" -mindepth 1 -maxdepth 1 -type d "${age[@]}" -printf '%f\n' 2>/dev/null |
  while IFS= read -r name; do
    [ "$name" = "global" ] && continue
    grep -qxF "$name" "$projids" || printf '%s\n' "$SNAP_DIR/$name"
  done > "$orphans"
  if [ -s "$orphans" ]; then
    if [ "$DRY_RUN" = "1" ]; then
      log "DRY RUN - would delete $(wc -l < "$orphans") orphan snapshot dirs:"
      sed 's/^/  /' "$orphans"
    else
      while IFS= read -r d; do rm -rf -- "$d"; done < "$orphans"
      log "deleted $(wc -l < "$orphans") orphan snapshot dirs"
    fi
  else
    log "no orphan snapshot dirs"
  fi
fi
