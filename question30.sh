#Write a script that analyzes application logs for the previous day, 
#counts errors and warnings, generates a summary report, 
# and schedules execution using cron.
#ans) To analyze yesterday's application logs reliably in cron, compute the previous calendar date with date -d "yesterday" "+%Y-%m-%d", filter only lines matching that date in a single awk pass to count ERROR and WARNING entries, write a clean summary report to stdout and a report file, and use a self-contained cron entry (with explicit PATH, TZ if needed, and full file paths) so scheduled runs never fail due to minimal cron environment defaults.
#!/bin/bash

LOG_FILE="${1:-${LOG_FILE:-/var/log/app/application.log}}"
TARGET_DATE="${TARGET_DATE:-$(date -d "yesterday" "+%Y-%m-%d")}"
REPORT_FILE="${REPORT_FILE:-/var/log/app/daily_summary_${TARGET_DATE}.txt}"

if [ -z "$LOG_FILE" ]; then
  echo "Error: Log file path is required." >&2
  echo "Usage: $0 [log_file]" >&2
  echo "Optional env vars: TARGET_DATE (YYYY-MM-DD, default yesterday), REPORT_FILE" >&2
  exit 1
fi

if [ ! -f "$LOG_FILE" ] || [ ! -r "$LOG_FILE" ]; then
  echo "Error: Log file '$LOG_FILE' is missing or not readable." >&2
  exit 1
fi

if ! [[ "$TARGET_DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  echo "Error: Invalid TARGET_DATE '$TARGET_DATE'. Expected YYYY-MM-DD." >&2
  exit 1
fi

report_dir=$(dirname "$REPORT_FILE")
mkdir -p "$report_dir"
if [ ! -d "$report_dir" ] || [ ! -w "$report_dir" ]; then
  echo "Error: Report directory '$report_dir' is not writable." >&2
  exit 1
fi

tmp_err_file=$(mktemp)
trap 'rm -f "$tmp_err_file"' EXIT

# Single awk pass over LOG_FILE: filter TARGET_DATE, count ERROR and WARNING entries,
# and collect normalized error messages for ranking
read -r total_matched err_count warn_count < <(
  awk -v target_date="$TARGET_DATE" -v err_out="$tmp_err_file" '
    index($0, target_date) > 0 {
      matched++

      if ($0 ~ /(^|[^A-Za-z])(ERROR|ERR)([^A-Za-z]|$)/) {
        err++
        msg = $0
        sub(/^.*(ERROR|ERR)\]?:?[[:space:]]*/, "", msg)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", msg)
        if (length(msg) > 0) {
          print msg >> err_out
        }
      } else if ($0 ~ /(^|[^A-Za-z])(WARNING|WARN)([^A-Za-z]|$)/) {
        warn++
      }
    }
    END {
      printf "%d %d %d\n", matched + 0, err + 0, warn + 0
    }
  ' "$LOG_FILE"
)

{
  echo "=========================================================================="
  echo "DAILY APPLICATION LOG SUMMARY REPORT"
  echo "Generated At : $(date "+%Y-%m-%d %H:%M:%S %Z")"
  echo "Log Date     : $TARGET_DATE"
  echo "Source Log   : $LOG_FILE"
  echo "=========================================================================="
  printf "%-28s : %d\n" "Matched Log Lines (${TARGET_DATE})" "$total_matched"
  printf "%-28s : %d\n" "Total ERROR Entries" "$err_count"
  printf "%-28s : %d\n" "Total WARNING Entries" "$warn_count"
  echo "--------------------------------------------------------------------------"
  echo "Top Error Messages (${TARGET_DATE}):"

  if [ -s "$tmp_err_file" ]; then
    sort "$tmp_err_file" | uniq -c | sort -rn | head -n 5 | awk '
      {
        cnt = $1
        $1 = ""
        sub(/^[[:space:]]+/, "", $0)
        printf "  %4d x %s\n", cnt, $0
      }
    '
  else
    echo "  (No ERROR entries recorded for $TARGET_DATE)"
  fi

  echo "=========================================================================="
} | tee "$REPORT_FILE"

echo "Summary report saved to: $REPORT_FILE"

if [ "$err_count" -gt 0 ]; then
  exit 2
elif [ "$warn_count" -gt 0 ]; then
  exit 1
fi
exit 0

#Previous-day date calculation (date -d "yesterday" "+%Y-%m-%d"): Automatically targets yesterday's date (2026-11-26 when run on 2026-11-27) and names the report daily_summary_YYYY-MM-DD.txt so daily runs never overwrite each other.

#Single-pass awk filtering and counting: Scans $LOG_FILE once, keeps only lines containing $TARGET_DATE, counts ERROR/ERR and WARNING/WARN entries on word boundaries, and writes normalized error messages to a temporary file (mktemp + trap cleanup) without race conditions.

#Report generation and exit codes: Writes the formatted summary to both stdout and $REPORT_FILE via tee, returning exit code 2 when errors exist, 1 when only warnings exist, and 0 when clean.