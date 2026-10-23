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
#  3. Back up the DB (gzipped) to ~/Downloads before anything is written.
#  4. Optionally prune sessions with no activity for SESSION_MAX_AGE_DAYS.
#  5. Delete snapshot/<project-id>/ git dirs for projects no longer in the DB.
#  6. Rotate/truncate opencode.log and this script's own maintenance.log when
#     they grow past LOG_MAX_MB.
#  7. VACUUM the DB.
#
# Run from a terminal it asks four questions up front (backup, dead-path grace,
# session age, VACUUM) and Enter accepts the default. With no tty - cron or
# systemd --user - it runs unattended: VACUUM on, backup off, no age prune
# unless SESSION_MAX_AGE_DAYS is set. Every variable below still overrides its
# prompt, so a timer can pin any choice.
#
# Safe from cron / systemd --user. All filesystem/DB writes are skipped while
# OpenCode is running.
#
# Overrides (env):
#   BACKUP=1            back up the DB first (interactive default; off unattended)
#   BACKUP_DIR=$HOME/Downloads   where backups go
#   BACKUP_KEEP=3       gzipped backups to keep, oldest removed
#   DEAD_GRACE_DAYS=7   days a path must stay missing before pruning
#   SESSION_MAX_AGE_DAYS=0  inactive days before a session is eligible (0 = off)
#   ASSUME_YES=0        set 1 to delete ripe sessions without confirming
#   LOG_MAX_MB=50       rotate the log above this size (0 disables)
#   LOG_KEEP=3          number of .gz archives to keep
#   DO_VACUUM=1         VACUUM the DB each run (0 = skip; needs OpenCode closed)
#   ROOTS=...           space-separated whitelist of path roots
#   SNAP_DIR=...        snapshot store (default $OC_DIR/snapshot)
#   DRY_RUN=1           report only, never prompts
set -euo pipefail

OC_DIR="${OC_DIR:-$HOME/.local/share/opencode}"
DB="${OC_DB:-$OC_DIR/opencode.db}"
LOG="${OC_LOG:-$OC_DIR/log/opencode.log}"
SNAP_DIR="${SNAP_DIR:-$OC_DIR/snapshot}"
STATE_DIR="${OC_STATE:-$HOME/.local/state/opencode}/maintenance"
STATE_FILE="$STATE_DIR/dead_paths.tsv"
MAINT_LOG="$STATE_DIR/maintenance.log"

# Prompt-backed settings start empty so the choices block can tell "unset" from
# "chosen"; the rest have fixed defaults.
DEAD_GRACE_DAYS="${DEAD_GRACE_DAYS:-}"
SESSION_MAX_AGE_DAYS="${SESSION_MAX_AGE_DAYS:-}"
DO_VACUUM="${DO_VACUUM:-}"
BACKUP="${BACKUP:-}"
ASSUME_YES="${ASSUME_YES:-0}"
LOG_MAX_MB="${LOG_MAX_MB:-50}"
LOG_KEEP="${LOG_KEEP:-3}"
BACKUP_DIR="${BACKUP_DIR:-$HOME/Downloads}"
BACKUP_KEEP="${BACKUP_KEEP:-3}"
DRY_RUN="${DRY_RUN:-0}"
ROOTS=(${ROOTS:-"$HOME/Projects"})

mkdir -p "$STATE_DIR"

# shift archives, gzip the current file, truncate in place (copytruncate keeps
# an app's open fd valid, so this is safe while something is writing to it)
rotate_log() {
  local f="$1" keep="$2" i
  i=$keep
  while [ "$i" -gt 1 ]; do
    [ -f "$f.$((i-1)).gz" ] && mv -f "$f.$((i-1)).gz" "$f.$i.gz"
    i=$((i-1))
  done
  cp -a "$f" "$f.1" && gzip -f "$f.1"
  : > "$f"
}

exec > >(tee -a "$MAINT_LOG") 2>&1
# process substitution is not waited for: close the pipe so tee flushes the last
# lines into the transcript before the script (or a systemd scope) goes away
trap 'exec 1>&- 2>&-; wait' EXIT
log() { printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*"; }

# This transcript only grows a line or two per run, but it is still unbounded;
# cap it with the same thresholds as opencode's own log.
maint_mb=0
if [ "$LOG_MAX_MB" -gt 0 ] && [ -f "$MAINT_LOG" ]; then
  maint_mb=$(( $(stat -c %s "$MAINT_LOG") / 1048576 ))
fi
if [ "$maint_mb" -gt 0 ] && [ "$maint_mb" -ge "$LOG_MAX_MB" ]; then
  if [ "$DRY_RUN" = "1" ]; then
    log "DRY RUN - would rotate maintenance log (${maint_mb}MB >= ${LOG_MAX_MB}MB)"
  else
    rotate_log "$MAINT_LOG" "$LOG_KEEP"
    log "rotated maintenance log (${maint_mb}MB) -> $(basename "$MAINT_LOG").1.gz"
  fi
fi

# human-readable bytes; dir_bytes sizes a tree, db page stats come from python
hr() { awk -v b="${1:-0}" 'BEGIN{split("B KiB MiB GiB TiB",u," ");i=1;while(b>=1024&&i<5){b/=1024;i++}printf (i==1?"%d %s":"%.1f %s"),b,u[i]}'; }
dir_bytes() { du -sb -- "$1" 2>/dev/null | cut -f1; }

ask_num() {  # ask_num VAR label default
  local v
  while :; do
    printf '%s [%s] ' "$2" "$3"
    read -r v || v=""
    v="${v:-$3}"
    case "$v" in *[!0-9]*) printf '  whole number, please\n';; *) break;; esac
  done
  printf -v "$1" '%s' "$v"
}

ask_yn() {  # ask_yn VAR label default(y/n)
  local v="" d="${3:-y}" hint
  case "$d" in y|Y|yes|YES) hint="Y/n";; *) hint="y/N";; esac
  printf '%s [%s] ' "$2" "$hint"
  read -r v || v=""
  case "${v:-$d}" in y|Y|yes|YES) printf -v "$1" 1;; *) printf -v "$1" 0;; esac
}

backup_db() {
  local tmp="$TMPD/backup.db" dest old
  dest="$BACKUP_DIR/opencode-db-$(date +%Y%m%d-%H%M%S).db.gz"
  if ! sqlite3 "$DB" ".backup '$tmp'"; then
    log "backup failed - aborting before any write"
    exit 1
  fi
  if ! gzip -c "$tmp" > "$dest"; then
    rm -f "$dest"
    log "backup failed - no space in $BACKUP_DIR? aborting before any write"
    exit 1
  fi
  log "backup: $dest ($(hr "$(stat -c %s "$dest")"))"
  while IFS= read -r old; do
    rm -f -- "$old"; log "backup: removed old $(basename "$old")"
  done < <(ls -1t "$BACKUP_DIR"/opencode-db-*.db.gz 2>/dev/null | tail -n +$(( BACKUP_KEEP + 1 )))
}

db_size_before=0 db_size_after=0
db_reclaim=0 snap_bytes=0 log_bytes=0

# single instance
exec 9>"$STATE_DIR/.lock"
flock -n 9 || { log "another run in progress"; exit 0; }

# scratch space for the pre-write DB copy and the prune lists; cleared on exit,
# including Ctrl-C, but deliberately not /tmp - that is tmpfs here and the copy
# is DB-sized.
TMPD=$(mktemp -d -p "$STATE_DIR" maint.XXXXXX)
trap 'rm -rf "$TMPD"' EXIT

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

# table_exists <name> - false when the table is absent (schema changes between
# OpenCode versions)
table_exists() {
  [ "$(sqlite3 "$DB" "SELECT count(*) FROM pragma_table_info('$1');")" -gt 0 ]
}

# column_exists <table> <column> - false when either is absent
column_exists() {
  [ "$(sqlite3 "$DB" "SELECT count(*) FROM pragma_table_info('$1') WHERE name='$2';")" -gt 0 ]
}

# ------------------------------------------------------------------- choices
if [ -t 0 ] && [ "$DRY_RUN" != "1" ]; then
  if oc_running; then log "warning: OpenCode is running - DB backup, prune and VACUUM will be skipped"; fi
  [ -n "$BACKUP" ] || ask_yn BACKUP "Back up the DB to $BACKUP_DIR (keep $BACKUP_KEEP)" y
  [ -n "$DEAD_GRACE_DAYS" ] || ask_num DEAD_GRACE_DAYS "Days a missing project path must stay gone before pruning" 7
  [ -n "$SESSION_MAX_AGE_DAYS" ] || ask_num SESSION_MAX_AGE_DAYS "Prune sessions inactive longer than (days, 0 = never)" 60
  [ -n "$DO_VACUUM" ] || ask_yn DO_VACUUM "VACUUM the DB at the end" y
fi
# Unattended defaults; a dry run mirrors the interactive ones so it still shows
# the full plan.
if [ "$DRY_RUN" = "1" ]; then
  BACKUP="${BACKUP:-1}"
  SESSION_MAX_AGE_DAYS="${SESSION_MAX_AGE_DAYS:-60}"
else
  BACKUP="${BACKUP:-0}"
  SESSION_MAX_AGE_DAYS="${SESSION_MAX_AGE_DAYS:-0}"
fi
DEAD_GRACE_DAYS="${DEAD_GRACE_DAYS:-7}"
DO_VACUUM="${DO_VACUUM:-1}"
log "choices: backup=$BACKUP grace=${DEAD_GRACE_DAYS}d age-prune=${SESSION_MAX_AGE_DAYS}d vacuum=$DO_VACUUM"

# ------------------------------------------------------------------ log rotation
if [ "$LOG_MAX_MB" -gt 0 ] && [ -f "$LOG" ]; then
  size_mb=$(( $(stat -c %s "$LOG") / 1048576 ))
  if [ "$size_mb" -ge "$LOG_MAX_MB" ]; then
    if [ "$DRY_RUN" = "1" ]; then
      log "DRY RUN - would rotate log (${size_mb}MB >= ${LOG_MAX_MB}MB)"
    else
      log_bytes=$(( size_mb * 1048576 ))
      rotate_log "$LOG" "$LOG_KEEP"
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

# ---------------------------------------------------------------- db backup
if [ "$BACKUP" = "1" ]; then
  if [ "$skip_db" = 1 ]; then
    log "backup skipped - OpenCode running"
  elif [ "$DRY_RUN" = "1" ]; then
    log "DRY RUN - would back up $DB to $BACKUP_DIR"
  else
    mkdir -p "$BACKUP_DIR"
    backup_db
  fi
fi

tmp="$TMPD/dead_paths"; ripe="$TMPD/ripe"; newstate="$TMPD/newstate"

for pair in "session directory" "session_v2 directory" "project worktree" "project_directory directory" "worktree directory"; do
  set -- $pair
  # columns come and go between OpenCode versions; skip a pair that no longer exists
  sqlite3 "$DB" "SELECT 1 FROM pragma_table_info('$1') WHERE name='$2';" | grep -qx 1 || continue
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
  # A dry run never writes the state file, so a fresh state has nothing ripe;
  # list the candidates so the preview still shows what is being tracked.
  if [ -s "$tmp" ]; then
    log "DRY RUN - missing paths under ROOTS (grace ${DEAD_GRACE_DAYS}d before any is pruned):"
    sed 's/^/  /' "$tmp"
  fi
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

# the dry-run branch only prints, so it may run while OpenCode is open
if [ -s "$ripe" ] && { [ "$DRY_RUN" = 1 ] || [ "$skip_db" = 0 ]; }; then
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
have = {r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type='table'")}
def cols(t): return {r[1] for r in con.execute(f"PRAGMA table_info('{t}')")}
def has(t, *names):
    return t in have and all(n in cols(t) for n in names)
def count(t): return con.execute(f"SELECT count(*) FROM {t}").fetchone()[0]
counted = [t for t in ("session_v2", "session_message", "message", "part") if t in have]
before = {t: count(t) for t in counted}
def run(s): return con.execute(s, paths).rowcount
deleted = {}
for t in ("session", "session_v2", "project_directory", "worktree"):
    if has(t, "directory"):
        deleted[t] = run(f"DELETE FROM {t} WHERE directory IN ({q})")
sessions = [t for t in ("session", "session_v2") if has(t, "project_id")]
if has("project", "worktree", "id") and sessions:
    keep = " UNION ".join(f"SELECT DISTINCT project_id FROM {t}" for t in sessions)
    deleted["project"] = run(f"DELETE FROM project WHERE worktree IN ({q}) AND id NOT IN ({keep})")
after = {t: count(t) for t in counted}
con.commit()
ps = con.execute("PRAGMA page_size").fetchone()[0]
reclaim = con.execute("PRAGMA freelist_count").fetchone()[0] * ps
con.execute("PRAGMA optimize")
print("deleted " + " ".join(f"{t}={n}" for t, n in deleted.items()))
print("cascaded " + " ".join(f"{t}={before[t]-after[t]}" for t in counted))
print(f"reclaim={reclaim}")
con.close()
PY
)
    rc=$(printf '%s\n' "$out" | sed -n 's/^reclaim=//p')
    # each reading is the running freelist total, so it replaces the previous one
    db_reclaim=${rc:-$db_reclaim}
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
  if ! table_exists session || ! table_exists session_v2; then
    log "legacy session tables absent - nothing to drop"
  else
    n_mirror=$(sqlite3 "$DB" "SELECT count(*) FROM session WHERE id IN (SELECT id FROM session_v2);")
    if [ "$n_mirror" -gt 0 ]; then
      if [ "$DRY_RUN" = "1" ]; then
        log "DRY RUN - would drop $n_mirror legacy session rows mirrored in session_v2"
      else
        sqlite3 "$DB" "PRAGMA foreign_keys=ON; DELETE FROM session WHERE id IN (SELECT id FROM session_v2);"
        ps=$(sqlite3 "$DB" "PRAGMA page_size;")
        db_reclaim=$(( $(sqlite3 "$DB" "PRAGMA freelist_count;") * ps ))
        log "legacy prune: dropped $n_mirror mirrored session rows; $(sqlite3 "$DB" "SELECT count(*) FROM session;") legacy sessions left"
      fi
    else
      log "no legacy session rows to drop"
    fi
  fi
fi

# ------------------------------------------------------------- age-based prune
# Sessions are pruned by last activity (time_updated, epoch ms). Deleting a
# session row cascades to messages, parts, todos, etc. (requires foreign_keys).
if [ "$skip_db" = 0 ] && [ "${SESSION_MAX_AGE_DAYS:-0}" -gt 0 ] 2>/dev/null && column_exists session_v2 time_updated; then
  age_days="$SESSION_MAX_AGE_DAYS"
  now=$(date +%s)
  cutoff_ms=$(( (now - age_days * 86400) * 1000 ))
  n_old=$(sqlite3 "$DB" "SELECT count(*) FROM session_v2 WHERE time_updated <= $cutoff_ms;")
  log "sessions inactive >${age_days}d: $n_old"
  if [ "$n_old" -gt 0 ]; then
    if [ "$DRY_RUN" = "1" ]; then
      log "DRY RUN - would prune $n_old sessions older than ${age_days}d"
    else
      proceed=1
      if [ "$ASSUME_YES" != "1" ]; then
        if [ -t 0 ]; then
          printf 'Delete %s sessions unused for at least %s days? [y/N] ' "$n_old" "$age_days"
          read -r reply || reply=""
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
have = {r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type='table'")}
def cols(t): return {r[1] for r in con.execute(f"PRAGMA table_info('{t}')")}
counted = [t for t in ("session_v2", "session", "session_message", "message", "part") if t in have]
def count(t): return con.execute(f"SELECT count(*) FROM {t}").fetchone()[0]
before = {t: count(t) for t in counted}
deleted = {}
for t in ("session_v2", "session"):
    if t in have and "time_updated" in cols(t):
        deleted[t] = con.execute(f"DELETE FROM {t} WHERE time_updated <= ?", (cutoff,)).rowcount
con.commit()
after = {t: count(t) for t in counted}
ps = con.execute("PRAGMA page_size").fetchone()[0]
reclaim = con.execute("PRAGMA freelist_count").fetchone()[0] * ps
con.execute("PRAGMA optimize")
print("deleted " + ", ".join(f"{t}={n}" for t, n in deleted.items()))
print(f"reclaim={reclaim}")
con.close()
PY
)
        rc=$(printf '%s\n' "$out" | sed -n 's/^reclaim=//p')
        db_reclaim=${rc:-$db_reclaim}
        log "pruned sessions older than ${age_days}d: $(printf '%s\n' "$out" | grep -v '^reclaim=' | paste -sd'; ' -)"
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
if [ ! -d "$SNAP_DIR" ]; then
  :
elif ! table_exists project; then
  log "project table absent - snapshot cleanup skipped"
else
  projids="$TMPD/projids"; orphans="$TMPD/orphans"
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
