#!/usr/bin/env bash
# opencode-maintenance.sh - periodic maintenance for OpenCode
#
# `DRY_RUN=1 bash /home/bubba/Projects/_scripts/src/opencode-maintenance.sh`
# `bash /home/bubba/Projects/_scripts/src/opencode-maintenance.sh`
#
#  1. Prune OpenCode SQLite rows whose project directory no longer exists
#     (prevents "Failed to send prompt / Unable to retrieve session").
#     A path must be missing for DEAD_GRACE_DAYS before it is pruned.
#  2. Drop the frozen legacy session/message/part rows that OpenCode migrated
#     to session_v2/session_message (only rows mirrored in session_v2).
#  3. Optionally prune sessions with no activity for SESSION_MAX_AGE_DAYS
#     (interactive y/N when run on a tty; ASSUME_YES=1 for unattended).
#  4. Delete snapshot/<project-id>/ git dirs for projects no longer in the DB.
#  5. Rotate/truncate opencode.log when it grows past LOG_MAX_MB.
#  6. VACUUM the DB.
#
# Safe from cron / systemd --user. All filesystem/DB writes are skipped while
# OpenCode is running.
#
# Tunables (env):
#   DEAD_GRACE_DAYS=7   days a path must stay missing before pruning
#   SESSION_MAX_AGE_DAYS  inactive days before a session is eligible; unset asks
#                       interactively (default prompt 60d), 0 disables age prune
#   ASSUME_YES=0        set 1 to skip the interactive age-prune confirmation
#   LOG_MAX_MB=50       rotate the log above this size (0 disables)
#   LOG_KEEP=3          number of .gz archives to keep
#   DO_VACUUM=1         VACUUM the DB each run (set 0 to skip; needs OpenCode closed)
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
SESSION_MAX_AGE_DAYS="${SESSION_MAX_AGE_DAYS:-}"
SESSION_MAX_AGE_PROMPT_DAYS="${SESSION_MAX_AGE_PROMPT_DAYS:-60}"
ASSUME_YES="${ASSUME_YES:-0}"
LOG_MAX_MB="${LOG_MAX_MB:-50}"
LOG_KEEP="${LOG_KEEP:-3}"
DO_VACUUM="${DO_VACUUM:-1}"
DRY_RUN="${DRY_RUN:-0}"
ROOTS=(${ROOTS:-"$HOME/Projects"})

mkdir -p "$STATE_DIR"
exec > >(tee -a "$MAINT_LOG") 2>&1
log() { printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*"; }

# human-readable bytes; dir_bytes sizes a tree, db page stats come from python
hr() { awk -v b="${1:-0}" 'BEGIN{split("B KiB MiB GiB TiB",u," ");i=1;while(b>=1024&&i<5){b/=1024;i++}printf (i==1?"%d %s":"%.1f %s"),b,u[i]}'; }
dir_bytes() { du -sb -- "$1" 2>/dev/null | cut -f1; }

db_size_before=0 db_size_after=0
db_reclaim=0 snap_bytes=0 log_bytes=0

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
      log_bytes=$(( size_mb * 1048576 ))
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
db_size_before=$(stat -c %s "$DB")
skip_db=0
if oc_running; then log "OpenCode running - skipping DB prune"; skip_db=1; fi

tmp=$(mktemp); ripe=$(mktemp); newstate=$(mktemp)
trap 'rm -f "$tmp" "$ripe" "$newstate"' EXIT

for pair in "session directory" "session_v2 directory" "project worktree" "project_directory directory" "workspace directory"; do
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
    sqlite3 "$DB" "PRAGMA wal_checkpoint(TRUNCATE);" >/dev/null
    out=$(python3 - "$DB" "$ripe" <<'PY'
import sqlite3, sys
db, listfile = sys.argv[1], sys.argv[2]
paths = [l.rstrip("\n") for l in open(listfile) if l.strip()]
if not paths:
    print("nothing ripe"); sys.exit(0)
q = ",".join("?" * len(paths))
con = sqlite3.connect(db)
con.execute("PRAGMA foreign_keys=ON")
con.execute("BEGIN")
def count(t): return con.execute(f"SELECT count(*) FROM {t}").fetchone()[0]
before = {t: count(t) for t in ("session_v2", "session_message", "message", "part")}
def run(s): return con.execute(s, paths).rowcount
n1 = run(f"DELETE FROM session           WHERE directory IN ({q})")
n2 = run(f"DELETE FROM session_v2        WHERE directory IN ({q})")
n3 = run(f"DELETE FROM project_directory WHERE directory IN ({q})")
n4 = run(f"DELETE FROM workspace         WHERE directory IN ({q})")
n5 = run(f"""DELETE FROM project
             WHERE worktree IN ({q})
               AND id NOT IN (SELECT DISTINCT project_id FROM session
                              UNION SELECT DISTINCT project_id FROM session_v2)""")
after = {t: count(t) for t in ("session_v2", "session_message", "message", "part")}
con.commit()
ps = con.execute("PRAGMA page_size").fetchone()[0]
reclaim = con.execute("PRAGMA freelist_count").fetchone()[0] * ps
con.execute("PRAGMA optimize")
print(f"deleted sessions={n1} sessions_v2={n2} project_directory={n3} workspace={n4} projects={n5}")
print("cascaded " + " ".join(f"{t}={before[t]-after[t]}" for t in before))
print(f"reclaim={reclaim}")
con.close()
PY
)
    rc=$(printf '%s\n' "$out" | sed -n 's/^reclaim=//p')
    db_reclaim=$(( db_reclaim + ${rc:-0} ))
    log "$(printf '%s\n' "$out" | grep -v '^reclaim=' | paste -sd'; ' -)"
    awk -F'\t' -v r="$ripe" '
      NR==FNR { dead[$1]=1; next }
      !($1 in dead)' "$ripe" "$STATE_FILE" > "$STATE_FILE.new" && mv "$STATE_FILE.new" "$STATE_FILE"
    log "db prune complete"
  fi
fi

# --------------------------------------------------------------- legacy tables
# OpenCode migrated session/message/part to session_v2/session_message; the old
# tables are frozen mirrors. Only rows also in session_v2 are dropped, so no
# history is lost; the FK cascade clears their message/part rows.
if [ "$skip_db" = 0 ]; then
  n_mirror=$(sqlite3 "$DB" "SELECT count(*) FROM session WHERE id IN (SELECT id FROM session_v2);")
  if [ "$n_mirror" -gt 0 ]; then
    if [ "$DRY_RUN" = "1" ]; then
      log "DRY RUN - would drop $n_mirror legacy session rows mirrored in session_v2"
    else
      sqlite3 "$DB" "PRAGMA foreign_keys=ON; DELETE FROM session WHERE id IN (SELECT id FROM session_v2);"
      ps=$(sqlite3 "$DB" "PRAGMA page_size;")
      db_reclaim=$(( db_reclaim + $(sqlite3 "$DB" "PRAGMA freelist_count;") * ps ))
      log "legacy prune: dropped $n_mirror mirrored session rows; $(sqlite3 "$DB" "SELECT count(*) FROM session;") legacy sessions left"
    fi
  else
    log "no legacy session rows to drop"
  fi
fi

# ------------------------------------------------------------- age-based prune
# Sessions are pruned by last activity (time_updated, epoch ms). Deleting a
# session row cascades to messages, parts, todos, etc. (requires foreign_keys).
if [ "$skip_db" = 0 ]; then
  age_days="$SESSION_MAX_AGE_DAYS"
  age_confirmed=0
  if [ -z "$age_days" ]; then
    if [ "$DRY_RUN" = "1" ]; then
      age_days="$SESSION_MAX_AGE_PROMPT_DAYS"
    elif [ -t 0 ]; then
      printf 'Prune sessions with no activity for %s days? [y/N] ' "$SESSION_MAX_AGE_PROMPT_DAYS"
      read -r reply
      case "$reply" in
        y|Y|yes|YES) age_days="$SESSION_MAX_AGE_PROMPT_DAYS"; age_confirmed=1;;
        *) age_days=0;;
      esac
    else
      log "no tty and SESSION_MAX_AGE_DAYS unset - skipping age prune"
      age_days=0
    fi
  fi

  if [ "$age_days" -gt 0 ] 2>/dev/null; then
    now=$(date +%s)
    cutoff_ms=$(( (now - age_days * 86400) * 1000 ))
    n_old=$(sqlite3 "$DB" "SELECT count(*) FROM session_v2 WHERE time_updated <= $cutoff_ms;")
    log "sessions inactive >${age_days}d: $n_old"
    if [ "$n_old" -gt 0 ]; then
      if [ "$DRY_RUN" = "1" ]; then
        log "DRY RUN - would prune $n_old sessions older than ${age_days}d"
      else
        proceed=1
        if [ "$age_confirmed" != 1 ] && [ "$ASSUME_YES" != "1" ]; then
          if [ -t 0 ]; then
            printf 'Delete %s sessions with no activity for %s days? [y/N] ' "$n_old" "$age_days"
            read -r reply
            case "$reply" in y|Y|yes|YES) ;; *) proceed=0;; esac
          else
            log "no tty and ASSUME_YES != 1 - skipping age prune"
            proceed=0
          fi
        fi
        if [ "$proceed" = 1 ]; then
          out=$(python3 - "$DB" "$cutoff_ms" <<'PY'
import sqlite3, sys
db, cutoff = sys.argv[1], int(sys.argv[2])
con = sqlite3.connect(db)
con.execute("PRAGMA foreign_keys=ON")
con.execute("BEGIN")
tables = ("session_v2", "session", "session_message", "message", "part")
def count(t): return con.execute(f"SELECT count(*) FROM {t}").fetchone()[0]
before = {t: count(t) for t in tables}
con.execute("DELETE FROM session_v2 WHERE time_updated <= ?", (cutoff,))
con.execute("DELETE FROM session    WHERE time_updated <= ?", (cutoff,))
con.commit()
after = {t: count(t) for t in tables}
ps = con.execute("PRAGMA page_size").fetchone()[0]
reclaim = con.execute("PRAGMA freelist_count").fetchone()[0] * ps
con.execute("PRAGMA optimize")
print("deleted " + ", ".join(f"{t}={before[t]-after[t]}" for t in tables))
print(f"reclaim={reclaim}")
con.close()
PY
)
          rc=$(printf '%s\n' "$out" | sed -n 's/^reclaim=//p')
          db_reclaim=$(( db_reclaim + ${rc:-0} ))
          log "pruned sessions older than ${age_days}d: $(printf '%s\n' "$out" | grep -v '^reclaim=' | paste -sd'; ' -)"
        fi
      fi
    fi
  fi
fi

# ------------------------------------------------------------------ vacuum
# On by default. Runs even when nothing was pruned, so freed/reusable pages
# from earlier runs are compacted in one go.
if [ "$DO_VACUUM" = "1" ]; then
  if [ "$skip_db" = 1 ]; then
    log "VACUUM skipped - OpenCode running (needs an exclusive lock)"
  elif [ "$DRY_RUN" = "1" ]; then
    log "DRY RUN - would VACUUM $DB"
  elif sqlite3 "$DB" "VACUUM;"; then
    log "VACUUM complete"
  else
    log "VACUUM failed"
  fi
fi

db_size_after=$(stat -c %s "$DB")

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
    while IFS= read -r d; do s=$(dir_bytes "$d"); snap_bytes=$((snap_bytes+${s:-0})); done < "$orphans"
    if [ "$DRY_RUN" = "1" ]; then
      log "DRY RUN - would delete $(wc -l < "$orphans") orphan snapshot dirs ($(hr "$snap_bytes")):"
      sed 's/^/  /' "$orphans"
    else
      while IFS= read -r d; do rm -rf -- "$d"; done < "$orphans"
      log "deleted $(wc -l < "$orphans") orphan snapshot dirs ($(hr "$snap_bytes"))"
    fi
  else
    log "no orphan snapshot dirs"
  fi
fi

# ------------------------------------------------------------------ summary
db_saved=$(( db_size_before - db_size_after )); [ "$db_saved" -lt 0 ] && db_saved=0
db_freed=$db_saved; [ "$db_reclaim" -gt "$db_freed" ] && db_freed=$db_reclaim
total_freed=$(( db_freed + snap_bytes + log_bytes ))
log "summary: db $(hr "$db_size_before") -> $(hr "$db_size_after") (file saved $(hr "$db_saved"), reusable $(hr "$db_reclaim")); snapshots $(hr "$snap_bytes"); log $(hr "$log_bytes"); total reclaimed $(hr "$total_freed")"
