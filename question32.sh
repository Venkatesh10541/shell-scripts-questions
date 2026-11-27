#Write a script that identifies eligible application logs, archives and 
#compresses them, and applies configurable retention policies.
# Include dry-run functionality, error logging, and protection 
# against deleting active log files. 
#ans) To safely archive, compress, and prune application logs without risking active files or accidental data loss, combine find with an active-handle check (lsof / fuser / /proc file-descriptor scan), verify every .tar.gz archive with tar -tzf before removing source logs, and gate destructive operations behind a DRY_RUN switch.
#!/bin/bash

LOG_DIR="${LOG_DIR:-${1:-/var/log/myapp}}"
ARCHIVE_DIR="${ARCHIVE_DIR:-${2:-/var/log/myapp/archive}}"
ERROR_LOG="${ERROR_LOG:-./log_archiver_errors.log}"
FILE_PATTERN="${FILE_PATTERN:-*.log}"
MIN_AGE_DAYS="${MIN_AGE_DAYS:-1}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
DRY_RUN="${DRY_RUN:-false}"

for arg in "$@"; do
  case "$arg" in
    --dry-run)
      DRY_RUN="true"
      ;;
  esac
done

case "$DRY_RUN" in
  true|TRUE|1|yes|YES) DRY_RUN="true" ;;
  *) DRY_RUN="false" ;;
esac

if [ -z "$LOG_DIR" ] || [ -z "$ARCHIVE_DIR" ]; then
  echo "Error: Both LOG_DIR and ARCHIVE_DIR must be specified." >&2
  exit 1
fi

if [ ! -d "$LOG_DIR" ] || [ ! -r "$LOG_DIR" ]; then
  echo "Error: Log directory '$LOG_DIR' does not exist or is not readable." >&2
  exit 1
fi

mkdir -p "$(dirname "$ERROR_LOG")"
if [ ! -d "$(dirname "$ERROR_LOG")" ] || [ ! -w "$(dirname "$ERROR_LOG")" ]; then
  echo "Error: Error log directory '$(dirname "$ERROR_LOG")' is not writable." >&2
  exit 1
fi

if [ "$DRY_RUN" = "false" ]; then
  mkdir -p "$ARCHIVE_DIR"
  if [ ! -d "$ARCHIVE_DIR" ] || [ ! -w "$ARCHIVE_DIR" ]; then
    echo "Error: Archive directory '$ARCHIVE_DIR' is not writable." >&2
    exit 1
  fi
fi

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

eligible_list="${work_dir}/eligible_logs.txt"
: > "$eligible_list"

log_info() {
  echo "[$(date "+%Y-%m-%d %H:%M:%S")] [INFO]  $1"
}

log_warn() {
  local msg="$1"
  local ts
  ts=$(date "+%Y-%m-%d %H:%M:%S")
  echo "[$ts] [WARN]  $msg" | tee -a "$ERROR_LOG" >&2
}

log_err() {
  local msg="$1"
  local ts
  ts=$(date "+%Y-%m-%d %H:%M:%S")
  echo "[$ts] [ERROR] $msg" | tee -a "$ERROR_LOG" >&2
}

# Resolve canonical path to guard against accidentally scanning ARCHIVE_DIR
real_log_dir=$(cd "$LOG_DIR" 2>/dev/null && pwd -P)
real_archive_dir=""
if [ -d "$ARCHIVE_DIR" ]; then
  real_archive_dir=$(cd "$ARCHIVE_DIR" 2>/dev/null && pwd -P)
fi

# Check whether any running process currently holds the file open
is_file_active() {
  local target="$1"
  local real_target

  real_target=$(readlink -f "$target" 2>/dev/null || printf "%s" "$target")

  if command -v lsof >/dev/null 2>&1; then
    if lsof -n -- "$real_target" >/dev/null 2>&1; then
      return 0
    fi
  fi

  if command -v fuser >/dev/null 2>&1; then
    if fuser -s "$real_target" >/dev/null 2>&1; then
      return 0
    fi
  fi

  # Fallback: scan open file descriptors under /proc
  local fd_link
  for fd_link in /proc/[0-9]*/fd/*; do
    [ -e "$fd_link" ] || continue
    if [ "$(readlink "$fd_link" 2>/dev/null)" = "$real_target" ]; then
      return 0
    fi
  done

  return 1
}

# 1. Discover eligible log files (exclude ARCHIVE_DIR and skip already-compressed archives)
find_args=("$real_log_dir")
if [ -n "$real_archive_dir" ] && [ "$real_archive_dir" != "$real_log_dir" ]; then
  find_args+=(-path "$real_archive_dir" -prune -o)
fi

find_args+=(
  -type f
  -name "$FILE_PATTERN"
  ! -name "*.gz"
  ! -name "*.tar"
  ! -name "*.bz2"
  ! -name "*.xz"
  -mtime +"$MIN_AGE_DAYS"
  -print0
)

skipped_active=0
while IFS= read -r -d '' filepath; do
  if [ ! -r "$filepath" ]; then
    log_err "Skipping unreadable log file: $filepath"
    continue
  fi

  if is_file_active "$filepath"; then
    log_warn "Protected active log file (open handle detected), skipping: $filepath"
    skipped_active=$((skipped_active + 1))
    continue
  fi

  printf "%s\n" "$filepath" >> "$eligible_list"
done < <(find "${find_args[@]}" 2>>"$ERROR_LOG" | sort -z)

eligible_count=$(wc -l < "$eligible_list" 2>/dev/null || echo 0)

log_info "Dry-Run Mode: $DRY_RUN | Eligible logs: $eligible_count | Skipped active: $skipped_active"

# 2. Archive, compress, verify, and remove archived source files
if [ "$eligible_count" -gt 0 ]; then
  timestamp=$(date "+%Y%m%d_%H%M%S")
  archive_path="${ARCHIVE_DIR%/}/app_logs_${timestamp}.tar.gz"

  if [ "$DRY_RUN" = "true" ]; then
    log_info "[DRY-RUN] Would create archive: $archive_path"
    while IFS= read -r src_file; do
      log_info "[DRY-RUN] Would archive and remove source log: $src_file"
    done < "$eligible_list"
  else
    log_info "Creating archive '$archive_path' from $eligible_count eligible log file(s)..."
    if ! tar -czf "$archive_path" -T "$eligible_list" 2>>"$ERROR_LOG"; then
      log_err "Failed to create archive '$archive_path'. Source log files were NOT removed."
      rm -f "$archive_path"
      exit 1
    fi

    if [ ! -s "$archive_path" ] || ! tar -tzf "$archive_path" >/dev/null 2>>"$ERROR_LOG"; then
      log_err "Archive integrity check failed for '$archive_path'. Removing corrupt archive; source logs preserved."
      rm -f "$archive_path"
      exit 1
    fi

    log_info "Verified archive '$archive_path' successfully."

    removed_count=0
    while IFS= read -r src_file; do
      # Re-check active handle immediately before removal to avoid race conditions
      if is_file_active "$src_file"; then
        log_warn "File became active before removal; keeping '$src_file'."
        continue
      fi

      if rm -f "$src_file" 2>>"$ERROR_LOG"; then
        removed_count=$((removed_count + 1))
      else
        log_err "Failed to remove archived source log '$src_file'."
      fi
    done < "$eligible_list"

    log_info "Removed $removed_count of $eligible_count archived source log file(s)."
  fi
else
  log_info "No eligible log files found to archive."
fi

# 3. Apply retention policy to old archives in ARCHIVE_DIR (never touching active logs)
if [ -d "$real_archive_dir" ]; then
  pruned_count=0
  while IFS= read -r -d '' old_archive; do
    if is_file_active "$old_archive"; then
      log_warn "Protected active archive file during retention cleanup: $old_archive"
      continue
    fi

    if [ "$DRY_RUN" = "true" ]; then
      log_info "[DRY-RUN] Would delete expired archive (older than ${RETENTION_DAYS} days): $old_archive"
      pruned_count=$((pruned_count + 1))
    else
      if rm -f "$old_archive" 2>>"$ERROR_LOG"; then
        log_info "Deleted expired archive: $old_archive"
        pruned_count=$((pruned_count + 1))
      else
        log_err "Failed to delete expired archive: $old_archive"
      fi
    fi
  done < <(find "$real_archive_dir" -maxdepth 1 -type f -name "*.tar.gz" -mtime +"$RETENTION_DAYS" -print0 2>>"$ERROR_LOG" | sort -z)

  log_info "Retention check complete (older than ${RETENTION_DAYS} days). Archives affected: $pruned_count"
fi

exit 0
#Active log protection (is_file_active + pre-delete re-check): Checks lsof, fuser, and /proc/[0-9]*/fd/* to detect any process with an open descriptor on a log file—and re-checks right before rm -f so a log written to mid-run is not deleted.

#Safe archive-then-remove pipeline: Writes candidate paths into a temp file (mktemp -d + trap cleanup), compresses with tar -czf ... -T, validates with tar -tzf, deletes any invalid archive immediately, and only deletes source logs after verification succeeds.

#Configurable retention policy: Scans $ARCHIVE_DIR for .tar.gz archives older than $RETENTION_DAYS (default 30 days), skipping any file with an active handle.

#Dry-run and error logging: DRY_RUN=true (or --dry-run) previews every archival and retention action without modifying files, while log_warn and log_err write timestamped issues to both stderr and $ERROR_LOG.